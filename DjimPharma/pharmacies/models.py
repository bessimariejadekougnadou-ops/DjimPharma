from django.contrib.auth.models import User
from django.core.exceptions import ValidationError
from django.db import models
from django.utils import timezone


class Pharmacie(models.Model):
    SOURCE_DONNEES_CHOIX = [
        ("local", "Base interne officielle"),
        ("google_places", "Google Places API"),
        ("onpt_officiel", "Ordre National des Pharmaciens (ONPT)"),
    ]

    STATUT_VERIFICATION_CHOIX = [
        ("verifiee_officielle", "Vérifiée Officielle (ONPT Togo)"),
        ("en_attente", "En attente de vérification"),
        ("non_officielle", "Non vérifiée"),
    ]

    nom = models.CharField(max_length=150)
    adresse = models.CharField(max_length=255)
    ville = models.CharField(max_length=100)
    quartier = models.CharField(max_length=100, blank=True)
    telephone = models.CharField(max_length=20, blank=True)
    est_de_garde = models.BooleanField(default=False)
    identifiant_as_pharm = models.CharField(max_length=100, unique=True)
    cle_api = models.CharField(
        max_length=128,
        blank=True,
        null=True,
        unique=True,
        db_index=True,
        verbose_name="Clé API synchronisation (ex: pca_live_...)",
    )
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    est_active = models.BooleanField(default=True)

    # Champs intégration Google Places & Données Dynamiques
    google_place_id = models.CharField(
        max_length=255,
        blank=True,
        null=True,
        unique=True,
        db_index=True,
    )
    source_donnees = models.CharField(
        max_length=50,
        choices=SOURCE_DONNEES_CHOIX,
        default="local",
    )
    statut_verification = models.CharField(
        max_length=35,
        choices=STATUT_VERIFICATION_CHOIX,
        default="verifiee_officielle",
    )
    source_verification = models.CharField(
        max_length=150,
        default="ONPT Togo",
        blank=True,
    )
    date_derniere_synchro = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["nom"]

    def __str__(self):
        return f"{self.nom} ({self.ville})"

    def generer_cle_api(self, forcer: bool = False) -> str:
        """Génère une clé API sécurisée (format pca_live_...) pour cette pharmacie."""
        import secrets
        if not self.cle_api or forcer:
            self.cle_api = f"pca_live_{secrets.token_hex(16)}"
            self.save(update_fields=["cle_api"])
        return self.cle_api

    def periode_garde_active(self):
        """Retourne la période de garde actuellement active et validée pour cette pharmacie."""
        maintenant = timezone.now()
        return (
            self.periodes_garde.filter(
                statut_validation="valide",
                date_debut__lte=maintenant,
                date_fin__gte=maintenant,
            )
            .order_by("-date_debut")
            .first()
        )

    def actualiser_statut_garde(self, save=True):
        """Calcule et met à jour dynamiquement est_de_garde en fonction de la période active."""
        active = self.periode_garde_active() is not None
        if self.est_de_garde != active:
            self.est_de_garde = active
            if save:
                self.save(update_fields=["est_de_garde"])
        return self.est_de_garde


class PeriodeGarde(models.Model):
    STATUT_CHOIX = [
        ("en_attente", "En attente de validation"),
        ("valide", "Validée"),
        ("rejete", "Rejetée"),
        ("expire", "Expirée"),
    ]

    pharmacie = models.ForeignKey(
        Pharmacie,
        on_delete=models.CASCADE,
        related_name="periodes_garde",
    )
    date_debut = models.DateTimeField(db_index=True)
    date_fin = models.DateTimeField(db_index=True)
    zone = models.CharField(
        max_length=100,
        blank=True,
        help_text="Zone ou secteur de garde (ex: Lomé Centre, Agoè, Bè, Kara Nord)",
    )
    source = models.CharField(
        max_length=200,
        default="Tableau officiel ONPT Togo",
        help_text="Organisme ou autorité source de l'information",
    )
    date_verification = models.DateTimeField(
        default=timezone.now,
        help_text="Date et heure de dernière vérification auprès de la source",
    )
    statut_validation = models.CharField(
        max_length=30,
        choices=STATUT_CHOIX,
        default="valide",
    )
    valide_par = models.ForeignKey(
        User,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="gardes_validees",
        help_text="Compte autorisé ayant validé la période",
    )
    commentaire = models.TextField(blank=True)
    date_creation = models.DateTimeField(auto_now_add=True)
    date_modification = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-date_debut"]
        verbose_name = "Période de garde"
        verbose_name_plural = "Périodes de garde"

    def clean(self):
        if self.date_debut and self.date_fin and self.date_fin <= self.date_debut:
            raise ValidationError("La date de fin doit être postérieure à la date de début.")

    def est_active(self):
        maintenant = timezone.now()
        return (
            self.statut_validation == "valide"
            and self.date_debut <= maintenant <= self.date_fin
        )

    def __str__(self):
        return f"{self.pharmacie.nom} [{self.date_debut:%d/%m/%Y %H:%M} -> {self.date_fin:%d/%m/%Y %H:%M}] ({self.statut_validation})"


class HistoriqueGarde(models.Model):
    ACTION_CHOIX = [
        ("CREATION", "Création de la période"),
        ("MODIFICATION", "Modification des dates ou zone"),
        ("VALIDATION", "Validation officielle"),
        ("REJET", "Rejet de la période"),
        ("EXPIRATION", "Clôture / Expiration automatique"),
        ("SYNCHRO_AUTOMATIQUE", "Synchronisation planifiée"),
    ]

    periode_garde = models.ForeignKey(
        PeriodeGarde,
        on_delete=models.CASCADE,
        related_name="historique",
        null=True,
        blank=True,
    )
    pharmacie = models.ForeignKey(
        Pharmacie,
        on_delete=models.CASCADE,
        related_name="historique_gardes",
        null=True,
        blank=True,
    )
    action = models.CharField(max_length=40, choices=ACTION_CHOIX)
    modifie_par = models.ForeignKey(
        User,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    details = models.JSONField(default=dict, blank=True)
    date_action = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date_action"]

    def __str__(self):
        return f"{self.action} - {self.pharmacie or (self.periode_garde.pharmacie if self.periode_garde else 'Garde')} ({self.date_action:%d/%m/%Y %H:%M})"
