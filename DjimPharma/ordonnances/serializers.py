from rest_framework import serializers

from .models import Ordonnance


class OrdonnanceSerializer(serializers.ModelSerializer):
    pharmacie_nom = serializers.CharField(source="pharmacie.nom", read_only=True)

    class Meta:
        model = Ordonnance
        fields = [
            "id",
            "pharmacie",
            "pharmacie_nom",
            "fichier",
            "note_patient",
            "commentaire_pharmacien",
            "date_envoi",
            "date_traitement",
            "statut",
        ]
        read_only_fields = ["date_envoi", "statut"]


class TraitementOrdonnanceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Ordonnance
        fields = ["statut", "commentaire_pharmacien"]
