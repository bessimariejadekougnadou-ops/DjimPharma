from django.db import transaction
from rest_framework import serializers

from medicaments.models import Medicament
from pharmacies.models import Pharmacie
from stocks.models import StockPharmacie
from utilisateurs.models import LivreurProfile

from .models import Commande, LigneCommande


class LigneCommandeSerializer(serializers.ModelSerializer):
    medicament_nom = serializers.CharField(source="medicament.nom", read_only=True)

    class Meta:
        model = LigneCommande
        fields = ["id", "medicament", "medicament_nom", "quantite", "prix_unitaire"]


class CommandeSerializer(serializers.ModelSerializer):
    pharmacie_nom = serializers.CharField(source="pharmacie.nom", read_only=True)
    livreur_nom = serializers.CharField(source="livreur.compte.get_full_name", read_only=True)
    lignes = LigneCommandeSerializer(source="lignecommande_set", many=True, read_only=True)

    class Meta:
        model = Commande
        fields = [
            "id",
            "reference",
            "pharmacie",
            "pharmacie_nom",
            "livreur",
            "livreur_nom",
            "date_commande",
            "statut",
            "mode_reception",
            "adresse_livraison",
            "montant_total",
            "mode_paiement",
            "statut_paiement",
            "lignes",
        ]


class LigneCommandeCreationSerializer(serializers.Serializer):
    medicament = serializers.PrimaryKeyRelatedField(queryset=Medicament.objects.all())
    quantite = serializers.IntegerField(min_value=1)


class CreerCommandeSerializer(serializers.Serializer):
    pharmacie = serializers.PrimaryKeyRelatedField(queryset=Pharmacie.objects.all())
    mode_reception = serializers.ChoiceField(choices=Commande.MODE_RECEPTION_CHOIX)
    mode_paiement = serializers.ChoiceField(
        choices=Commande.MODE_PAIEMENT_CHOIX,
        required=False,
        default="paiement_livraison",
    )
    adresse_livraison = serializers.CharField(required=False, allow_blank=True, max_length=255)
    lignes = LigneCommandeCreationSerializer(many=True, min_length=1)

    def validate(self, donnees):
        if not hasattr(self.context["request"].user, "profil"):
            raise serializers.ValidationError("Ce compte n'est pas un compte client.")

        if (
            donnees["mode_reception"] == "livraison"
            and not donnees.get("adresse_livraison", "").strip()
        ):
            raise serializers.ValidationError(
                {"adresse_livraison": "L'adresse est obligatoire pour une livraison."}
            )

        quantites_par_medicament = {}
        for ligne in donnees["lignes"]:
            medicament_id = ligne["medicament"].id
            quantites_par_medicament[medicament_id] = (
                quantites_par_medicament.get(medicament_id, 0) + ligne["quantite"]
            )

        for medicament_id, quantite in quantites_par_medicament.items():
            stock = StockPharmacie.objects.filter(
                pharmacie=donnees["pharmacie"],
                medicament_id=medicament_id,
                est_disponible=True,
                quantite__gte=quantite,
            ).first()

            if stock is None:
                raise serializers.ValidationError(
                    {"lignes": "Un des medicaments n'est pas disponible en quantite suffisante."}
                )

        return donnees

    @transaction.atomic
    def create(self, donnees):
        lignes = donnees.pop("lignes")
        pharmacie = donnees["pharmacie"]
        utilisateur = self.context["request"].user.profil

        # Regroupe les quantites si le meme medicament est envoye plusieurs fois.
        quantites_par_medicament = {}
        montant_total = 0
        for ligne in lignes:
            medicament_id = ligne["medicament"].id
            quantites_par_medicament[medicament_id] = (
                quantites_par_medicament.get(medicament_id, 0) + ligne["quantite"]
            )

        # Verrouille les stocks le temps de verifier et de retirer les quantites.
        stocks = {
            stock.medicament_id: stock
            for stock in StockPharmacie.objects.select_for_update().filter(
                pharmacie=pharmacie,
                medicament_id__in=quantites_par_medicament,
                est_disponible=True,
            )
        }

        for medicament_id, quantite in quantites_par_medicament.items():
            stock = stocks.get(medicament_id)

            if stock is None or stock.quantite < quantite:
                raise serializers.ValidationError(
                    {
                        "lignes": (
                            "Un des medicaments n'est plus disponible "
                            "en quantite suffisante."
                        )
                    }
                )

        commande = Commande.objects.create(utilisateur=utilisateur, **donnees)

        for ligne in lignes:
            medicament = ligne["medicament"]
            quantite = ligne["quantite"]
            stock = stocks[medicament.id]

            ligne_commande = LigneCommande.objects.create(
                commande=commande,
                medicament=medicament,
                quantite=quantite,
            )
            montant_total += ligne_commande.prix_unitaire * ligne_commande.quantite

            stock.quantite -= quantite
            stock.est_disponible = stock.quantite > 0
            stock.save(update_fields=["quantite", "est_disponible"])

        commande.montant_total = montant_total
        commande.save(update_fields=["montant_total"])

        return commande

    def to_representation(self, instance):
        return CommandeSerializer(instance).data


class CommandeStatutSerializer(serializers.ModelSerializer):
    livreur = serializers.PrimaryKeyRelatedField(
        queryset=LivreurProfile.objects.filter(est_disponible=True),
        required=False,
        allow_null=True,
    )

    class Meta:
        model = Commande
        fields = ["statut", "livreur", "statut_paiement"]

    def validate(self, donnees):
        commande = self.instance
        statut = donnees.get("statut", commande.statut)
        livreur = donnees.get("livreur", commande.livreur)

        if statut == "livree" and commande.mode_reception != "livraison":
            raise serializers.ValidationError(
                {"statut": "Seules les commandes en livraison peuvent etre livrees."}
            )
        if commande.mode_reception == "livraison" and statut in {"prete", "livree"} and not livreur:
            raise serializers.ValidationError(
                {"livreur": "Un livreur est requis pour cette commande."}
            )
        return donnees


class LivraisonStatutSerializer(serializers.ModelSerializer):
    class Meta:
        model = Commande
        fields = ["statut"]

    def validate_statut(self, valeur):
        if valeur not in {"en_preparation", "prete", "livree"}:
            raise serializers.ValidationError("Ce statut ne peut pas etre applique par le livreur.")
        return valeur
