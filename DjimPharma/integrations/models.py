from django.db import models
from pharmacies.models import Pharmacie


class AsPharmSyncLog(models.Model):
    """Historique des synchronisations entre le logiciel AS-Pharm d'une officine et DjimPharma."""

    TYPE_CHOIX = [
        ("stocks", "Synchronisation des stocks et prix"),
        ("commandes", "Extraction des commandes"),
        ("statut_commande", "Mise a jour statut commande"),
    ]

    STATUT_CHOIX = [
        ("succes", "Succes"),
        ("erreur", "Erreur"),
    ]

    pharmacie = models.ForeignKey(
        Pharmacie,
        on_delete=models.CASCADE,
        related_name="logs_as_pharm",
    )
    type_synchronisation = models.CharField(
        max_length=30,
        choices=TYPE_CHOIX,
        default="stocks",
    )
    statut = models.CharField(
        max_length=20,
        choices=STATUT_CHOIX,
        default="succes",
    )
    nb_elements_traites = models.PositiveIntegerField(default=0)
    details = models.JSONField(default=dict, blank=True)
    message = models.TextField(blank=True)
    date_synchronisation = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date_synchronisation"]

    def __str__(self):
        return f"{self.pharmacie.nom} - {self.type_synchronisation} ({self.statut})"
