from django.db import models

from pharmacies.models import Pharmacie
from utilisateurs.models import Utilisateur


class DemandeUrgence(models.Model):
    STATUT_CHOIX = [
        ("envoyee", "Envoyee"),
        ("en_cours", "En cours de traitement"),
        ("traitee", "Traitee"),
        ("annulee", "Annulee"),
    ]

    utilisateur = models.ForeignKey(Utilisateur, on_delete=models.CASCADE)
    pharmacie = models.ForeignKey(
        Pharmacie,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="urgences",
    )
    pharmacien = models.ForeignKey(
        "utilisateurs.PharmacienProfile",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="urgences",
    )
    telephone = models.CharField(max_length=20)
    adresse = models.CharField(max_length=255)
    besoin = models.TextField()
    date_demande = models.DateTimeField(auto_now_add=True)
    statut = models.CharField(
        max_length=20,
        choices=STATUT_CHOIX,
        default="envoyee",
    )

    def __str__(self):
        return f"Urgence {self.id} - {self.utilisateur.prenom} {self.utilisateur.nom}"
