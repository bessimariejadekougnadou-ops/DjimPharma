from rest_framework import serializers
from .models import AsPharmSyncLog
from commandes.models import Commande, LigneCommande


class AsPharmProduitItemSerializer(serializers.Serializer):
    """Represente un medicament et son stock tel qu'extrait de la base AS-Pharm."""
    nom = serializers.CharField(max_length=150)
    code_dci = serializers.CharField(max_length=100, required=False, allow_blank=True, default="")
    forme_dosage = serializers.CharField(max_length=100, required=False, allow_blank=True, default="")
    description = serializers.CharField(required=False, allow_blank=True, default="")
    est_essentiel = serializers.BooleanField(required=False, default=False)
    prix = serializers.DecimalField(max_digits=10, decimal_places=2)
    quantite = serializers.IntegerField(min_value=0)
    est_disponible = serializers.BooleanField(required=False, default=True)


class AsPharmSyncPayloadSerializer(serializers.Serializer):
    """Payload global envoye par le connecteur local AS-Pharm de l'officine."""
    identifiant_as_pharm = serializers.CharField(max_length=100)
    cle_secrete = serializers.CharField(max_length=128, required=False, allow_blank=True)
    produits = AsPharmProduitItemSerializer(many=True)


class AsPharmLigneCommandeSerializer(serializers.ModelSerializer):
    nom_medicament = serializers.CharField(source="medicament.nom", read_only=True)
    forme_dosage = serializers.CharField(source="medicament.forme_dosage", read_only=True)

    class Meta:
        model = LigneCommande
        fields = ["id", "nom_medicament", "forme_dosage", "quantite", "prix_unitaire"]


class AsPharmCommandeSerializer(serializers.ModelSerializer):
    lignes = AsPharmLigneCommandeSerializer(source="lignecommande_set", many=True, read_only=True)
    client_nom = serializers.CharField(source="utilisateur.nom", read_only=True)
    client_prenom = serializers.CharField(source="utilisateur.prenom", read_only=True)
    client_telephone = serializers.CharField(source="utilisateur.telephone", read_only=True)

    class Meta:
        model = Commande
        fields = [
            "id",
            "reference",
            "statut",
            "mode_reception",
            "adresse_livraison",
            "montant_total",
            "mode_paiement",
            "statut_paiement",
            "date_commande",
            "client_nom",
            "client_prenom",
            "client_telephone",
            "lignes",
        ]


class AsPharmUpdateCommandeStatutSerializer(serializers.Serializer):
    statut = serializers.ChoiceField(
        choices=[
            ("en_preparation", "En preparation"),
            ("prete", "Prete"),
            ("livree", "Livree"),
            ("annulee", "Annulee"),
        ]
    )
    motif = serializers.CharField(required=False, allow_blank=True, default="")
