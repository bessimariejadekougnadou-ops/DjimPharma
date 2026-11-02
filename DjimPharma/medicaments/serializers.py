from rest_framework import serializers
from .models import Medicament, DemandeDisponibilite
from pharmacies.models import Pharmacie


class MedicamentSerializer(serializers.ModelSerializer):
    """
    Serializer pour le catalogue officiel des médicaments.
    Sépare strictement le catalogue des stocks : aucune disponibilité inventaire
    n'est affirmée sans connexion directe temps-réel (AS-Pharma non encore connecté).
    """
    disponibilite_statut = serializers.SerializerMethodField()
    disponibilite_libelle = serializers.SerializerMethodField()
    disponibilite_message = serializers.SerializerMethodField()
    peut_contacter_pharmacie = serializers.SerializerMethodField()
    prix_min = serializers.SerializerMethodField()
    prix_max = serializers.SerializerMethodField()
    prix_indicatif = serializers.SerializerMethodField()
    nombre_pharmacies_disponibles = serializers.SerializerMethodField()
    pharmacies_disponibles = serializers.SerializerMethodField()
    statut_reglementaire_display = serializers.CharField(source="get_statut_reglementaire_display", read_only=True)

    class Meta:
        model = Medicament
        fields = [
            "id",
            "nom",
            "dci",
            "dosage",
            "forme_pharmaceutique",
            "presentation",
            "laboratoire_fabricant",
            "categorie_therapeutique",
            "niveaux_soins",
            "statut_reglementaire",
            "statut_reglementaire_display",
            "source_information",
            "identifiant_externe",
            "est_essentiel",
            "est_actif",
            "necessite_validation_manuelle",
            "description",
            # Champs de transparence et disponibilité temps réel
            "disponibilite_statut",
            "disponibilite_libelle",
            "disponibilite_message",
            "peut_contacter_pharmacie",
            "prix_min",
            "prix_max",
            "prix_indicatif",
            "nombre_pharmacies_disponibles",
            "pharmacies_disponibles",
        ]

    def _get_stocks_disponibles(self, obj):
        if not hasattr(obj, "_cached_stocks_dispo"):
            obj._cached_stocks_dispo = list(
                obj.stocks.filter(est_disponible=True, quantite__gt=0).select_related("pharmacie")
            )
        return obj._cached_stocks_dispo

    def get_disponibilite_statut(self, obj) -> str:
        stocks = self._get_stocks_disponibles(obj)
        if not stocks:
            return "non_confirmee"
        total_qte = sum(s.quantite for s in stocks)
        if total_qte <= 10:
            return "stock_faible"
        return "disponible"

    def get_disponibilite_libelle(self, obj) -> str:
        stocks = self._get_stocks_disponibles(obj)
        if not stocks:
            return "Disponibilité non confirmée"
        nb = len(stocks)
        return f"En stock ({nb} pharmacie{'s' if nb > 1 else ''})"

    def get_disponibilite_message(self, obj) -> str:
        stocks = self._get_stocks_disponibles(obj)
        if not stocks:
            return (
                "Aucun stock en temps réel n'est synchronisé pour ce médicament. "
                "Contactez directement une pharmacie ou une officine de garde pour vous assurer de sa disponibilité."
            )
        nb = len(stocks)
        return f"Ce médicament est actuellement disponible dans {nb} pharmacie(s) partenaire(s) à Lomé."

    def get_prix_min(self, obj):
        stocks = self._get_stocks_disponibles(obj)
        if not stocks:
            return None
        return int(min(s.prix for s in stocks))

    def get_prix_max(self, obj):
        stocks = self._get_stocks_disponibles(obj)
        if not stocks:
            return None
        return int(max(s.prix for s in stocks))

    def get_prix_indicatif(self, obj):
        stocks = self._get_stocks_disponibles(obj)
        if not stocks:
            return None
        p_min = int(min(s.prix for s in stocks))
        p_max = int(max(s.prix for s in stocks))
        if p_min == p_max:
            return f"{p_min:,} FCFA".replace(",", " ")
        return f"{p_min:,} - {p_max:,} FCFA".replace(",", " ")

    def get_nombre_pharmacies_disponibles(self, obj) -> int:
        return len(self._get_stocks_disponibles(obj))

    def get_pharmacies_disponibles(self, obj):
        stocks = self._get_stocks_disponibles(obj)
        res = []
        for s in stocks:
            p = s.pharmacie
            q = s.quantite
            res.append({
                "pharmacie_id": p.id,
                "nom": p.nom,
                "adresse": p.adresse,
                "ville": p.ville,
                "quartier": p.quartier or "",
                "telephone": p.telephone,
                "est_de_garde": p.est_de_garde,
                "latitude": p.latitude,
                "longitude": p.longitude,
                "prix": int(s.prix) if s.prix == int(s.prix) else float(s.prix),
                "quantite": q,
                "statut_stock": "DISPONIBLE" if q > 10 else "STOCK_FAIBLE",
                "code_externe": s.code_externe,
            })
        return res

    def get_peut_contacter_pharmacie(self, obj) -> bool:
        return True


class DemandeDisponibiliteSerializer(serializers.ModelSerializer):
    pharmacie_nom = serializers.CharField(source="pharmacie.nom", read_only=True)
    pharmacie_telephone = serializers.CharField(source="pharmacie.telephone", read_only=True)
    medicament_nom = serializers.CharField(source="medicament.nom", read_only=True)

    class Meta:
        model = DemandeDisponibilite
        fields = [
            "id",
            "medicament",
            "medicament_nom",
            "pharmacie",
            "pharmacie_nom",
            "pharmacie_telephone",
            "nom_patient",
            "telephone_patient",
            "ordonnance_url",
            "message",
            "statut",
            "date_creation",
            "date_reponse",
        ]
        read_only_fields = ["id", "statut", "date_creation", "date_reponse"]
