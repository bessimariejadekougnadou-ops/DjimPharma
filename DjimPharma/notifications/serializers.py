from rest_framework import serializers
from .models import Notification, PreferenceNotificationGarde


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = [
            "id",
            "titre",
            "message",
            "type_notification",
            "canal",
            "donnees_supplementaires",
            "est_lue",
            "date_creation",
        ]


class NotificationLueSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ["est_lue"]


class PreferenceNotificationGardeSerializer(serializers.ModelSerializer):
    class Meta:
        model = PreferenceNotificationGarde
        fields = [
            "ville",
            "zone",
            "rayon_km",
            "recevoir_alertes_garde",
            "fcm_token",
            "date_modification",
        ]
