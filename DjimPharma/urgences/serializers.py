from rest_framework import serializers

from .models import DemandeUrgence


class DemandeUrgenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = DemandeUrgence
        fields = [
            "id",
            "pharmacie",
            "telephone",
            "adresse",
            "besoin",
            "date_demande",
            "statut",
        ]
        read_only_fields = ["date_demande", "statut"]


class TraitementUrgenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = DemandeUrgence
        fields = ["statut"]
