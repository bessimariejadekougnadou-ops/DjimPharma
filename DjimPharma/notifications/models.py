from django.db import models
from utilisateurs.models import Utilisateur


class Notification(models.Model):
    TYPE_CHOIX = [
        ("commande", "Commande"),
        ("ordonnance", "Ordonnance"),
        ("urgence", "Urgence"),
        ("garde", "Pharmacie de garde"),
        ("information", "Information"),
    ]

    CANAL_CHOIX = [
        ("application", "Application"),
        ("push", "Push Mobile (FCM)"),
        ("email", "Email"),
        ("sms", "SMS"),
    ]

    utilisateur = models.ForeignKey(Utilisateur, on_delete=models.CASCADE, related_name="notifications")
    titre = models.CharField(max_length=150)
    message = models.TextField()
    type_notification = models.CharField(
        max_length=20,
        choices=TYPE_CHOIX,
        default="information",
    )
    est_lue = models.BooleanField(default=False)
    date_creation = models.DateTimeField(auto_now_add=True)
    canal = models.CharField(max_length=20, choices=CANAL_CHOIX, default="application")
    donnees_supplementaires = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["-date_creation"]

    def __str__(self):
        return f"{self.titre} - {self.utilisateur.prenom} {self.utilisateur.nom}"


class PreferenceNotificationGarde(models.Model):
    utilisateur = models.OneToOneField(
        Utilisateur,
        on_delete=models.CASCADE,
        related_name="preferences_garde",
    )
    ville = models.CharField(max_length=100, default="Lomé")
    zone = models.CharField(max_length=100, blank=True, help_text="Ex: Lomé Centre, Agoè, Bè")
    rayon_km = models.PositiveIntegerField(default=10)
    recevoir_alertes_garde = models.BooleanField(default=True)
    fcm_token = models.CharField(max_length=255, blank=True, help_text="Token Firebase Cloud Messaging")
    date_modification = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"Préférences garde de {self.utilisateur} ({self.ville})"
