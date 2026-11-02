from django.db import models

from pharmacies.models import Pharmacie
from utilisateurs.models import Utilisateur


class Ordonnance(models.Model):
    STATUT_CHOIX = [
        ("envoyee", "Envoyée"),
        ("en_cours", "En cours de traitement"),
        ("validee", "Validée"),
        ("rejetee", "Rejetée"),
    ]

    utilisateur = models.ForeignKey(Utilisateur, on_delete=models.CASCADE)
    pharmacie = models.ForeignKey(Pharmacie, on_delete=models.CASCADE)
    fichier = models.FileField(upload_to="ordonnances/")
    date_envoi = models.DateTimeField(auto_now_add=True)
    statut = models.CharField(
        max_length=20,
        choices=STATUT_CHOIX,
        default="envoyee",
    )
    note_patient = models.TextField(blank=True)
    commentaire_pharmacien = models.TextField(blank=True)
    date_traitement = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"Ordonnance {self.id} - {self.utilisateur.prenom} {self.utilisateur.nom}"
