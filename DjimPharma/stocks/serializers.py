from rest_framework import serializers
from .models import StockPharmacie


class StockPharmacieSerializer(serializers.ModelSerializer):
    pharmacie_nom = serializers.CharField(source="pharmacie.nom", read_only=True)
    pharmacie_ville = serializers.CharField(source="pharmacie.ville", read_only=True)
    pharmacie_adresse = serializers.CharField(source="pharmacie.adresse", read_only=True)
    pharmacie_telephone = serializers.CharField(source="pharmacie.telephone", read_only=True)
    pharmacie_est_de_garde = serializers.BooleanField(source="pharmacie.est_de_garde", read_only=True)

    medicament_nom = serializers.CharField(source="medicament.nom", read_only=True)
    medicament_forme_dosage = serializers.CharField(source="medicament.forme_dosage", read_only=True)
    medicament_dci = serializers.CharField(source="medicament.code_dci", read_only=True)
    medicament_est_essentiel = serializers.BooleanField(source="medicament.est_essentiel", read_only=True)

    class Meta:
        model = StockPharmacie
        fields = [
            "id",
            "pharmacie",
            "pharmacie_nom",
            "pharmacie_ville",
            "pharmacie_adresse",
            "pharmacie_telephone",
            "pharmacie_est_de_garde",
            "medicament",
            "medicament_nom",
            "medicament_forme_dosage",
            "medicament_dci",
            "medicament_est_essentiel",
            "quantite",
            "est_disponible",
            "prix",
            "derniere_synchronisation",
        ]


class GestionStockPharmacienSerializer(serializers.ModelSerializer):
    medicament_nom = serializers.CharField(source="medicament.nom", read_only=True)

    class Meta:
        model = StockPharmacie
        fields = [
            "id",
            "medicament",
            "medicament_nom",
            "quantite",
            "est_disponible",
            "prix",
            "derniere_synchronisation",
        ]
        read_only_fields = ["derniere_synchronisation"]

    def validate(self, donnees):
        quantite = donnees.get("quantite", getattr(self.instance, "quantite", 0))
        if quantite == 0:
            donnees["est_disponible"] = False
        return donnees
