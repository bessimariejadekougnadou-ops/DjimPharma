from rest_framework import serializers

from .models import AuditEtape, AuditSession


class AuditEtapeSerializer(serializers.ModelSerializer):
    class Meta:
        model = AuditEtape
        fields = [
            "id",
            "nom",
            "categorie",
            "statut",
            "description",
            "ordre",
            "details",
            "date_creation",
            "date_modification",
        ]


class AuditSessionSerializer(serializers.ModelSerializer):
    etapes = AuditEtapeSerializer(many=True, read_only=True)

    class Meta:
        model = AuditSession
        fields = [
            "id",
            "nom",
            "description",
            "is_active",
            "date_creation",
            "etapes",
        ]
