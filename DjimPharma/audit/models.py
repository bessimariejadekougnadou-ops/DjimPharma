from django.db import models


class AuditEtape(models.Model):
    """Représente une étape d’audit d’intégration ou de mise en œuvre."""

    CATEGORIE_CHOICES = [
        ("as_pharm", "AS PHARM"),
        ("clinicaa", "Clinicaa"),
        ("client", "Client"),
        ("securite", "Sécurité"),
        ("operationnel", "Opérationnel"),
    ]

    STATUT_CHOICES = [
        ("a_faire", "À faire"),
        ("en_cours", "En cours"),
        ("valide", "Validé"),
        ("bloque", "Bloquant"),
    ]

    nom = models.CharField(max_length=200)
    categorie = models.CharField(max_length=30, choices=CATEGORIE_CHOICES)
    statut = models.CharField(max_length=20, choices=STATUT_CHOICES, default="a_faire")
    description = models.TextField(blank=True)
    ordre = models.PositiveIntegerField(default=1)
    details = models.JSONField(default=dict, blank=True)
    date_creation = models.DateTimeField(auto_now_add=True)
    date_modification = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["ordre", "date_creation"]

    def __str__(self):
        return f"{self.nom} ({self.get_categorie_display()})"


class AuditSession(models.Model):
    """Regroupe les étapes d’un audit de projet ou d’intégration."""

    nom = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    date_creation = models.DateTimeField(auto_now_add=True)
    etapes = models.ManyToManyField(AuditEtape, blank=True)

    def __str__(self):
        return self.nom
