import unicodedata
from django.db import models
from django.utils import timezone


def normaliser_chaine(texte: str) -> str:
    """Normalise une chaîne pour la recherche : minuscules, suppression des accents et espaces superflus."""
    if not texte:
        return ""
    texte_sans_accents = "".join(
        c for c in unicodedata.normalize("NFD", texte)
        if unicodedata.category(c) != "Mn"
    )
    return " ".join(texte_sans_accents.lower().split())


class Medicament(models.Model):
    STATUT_REGLEMENTAIRE_CHOICES = [
        ("liste_essentielle_togo", "Inscrit sur la Liste Nationale des Médicaments Essentiels (Togo)"),
        ("amm_validee", "Autorisation de Mise sur le Marché (AMM validée)"),
        ("en_attente_validation", "En attente de validation réglementaire"),
        ("non_precise", "Non précisé"),
    ]

    # Champs principaux du catalogue
    nom = models.CharField(max_length=200, db_index=True, verbose_name="Nom commercial ou usuel")
    dci = models.CharField(max_length=200, blank=True, db_index=True, verbose_name="DCI (Dénomination Commune Internationale)")
    dosage = models.CharField(max_length=150, blank=True, verbose_name="Dosage")
    forme_pharmaceutique = models.CharField(max_length=150, blank=True, verbose_name="Forme pharmaceutique")
    presentation = models.CharField(max_length=200, blank=True, verbose_name="Présentation / Conditionnement")
    laboratoire_fabricant = models.CharField(max_length=150, blank=True, verbose_name="Laboratoire fabricant")
    categorie_therapeutique = models.CharField(max_length=250, blank=True, db_index=True, verbose_name="Catégorie / Classe thérapeutique")
    niveaux_soins = models.CharField(max_length=150, blank=True, verbose_name="Niveaux d'utilisation recommandés")

    # Statut réglementaire et traçabilité officielle
    # IMPORTANT : l'inscription à la LNME ne vaut PAS attribution automatique d'AMM
    statut_reglementaire = models.CharField(
        max_length=50,
        choices=STATUT_REGLEMENTAIRE_CHOICES,
        default="liste_essentielle_togo",
        verbose_name="Statut réglementaire",
    )
    source_information = models.CharField(
        max_length=255,
        default="Arrêté N° 147/2021/MSHPAUS - LNME Togo",
        verbose_name="Source officielle",
    )
    identifiant_externe = models.CharField(max_length=100, blank=True, db_index=True, verbose_name="Identifiant officiel externe")
    date_importation = models.DateTimeField(default=timezone.now, verbose_name="Date d'importation")
    derniere_mise_a_jour = models.DateTimeField(auto_now=True, verbose_name="Dernière mise à jour")
    est_actif = models.BooleanField(default=True, verbose_name="Actif dans le catalogue")

    # Contrôle qualité et validation manuelle
    necessite_validation_manuelle = models.BooleanField(default=False, verbose_name="Nécessite validation manuelle")
    notes_validation = models.TextField(blank=True, verbose_name="Notes de contrôle qualité")

    # Recherche normalisée
    nom_normalise = models.CharField(max_length=350, blank=True, db_index=True, verbose_name="Index normalisé (sans accents)")

    # Champs conservés pour rétrocompatibilité
    code_dci = models.CharField(max_length=200, blank=True, verbose_name="Code DCI (historique)")
    forme_dosage = models.CharField(max_length=200, blank=True, verbose_name="Forme & Dosage (historique)")
    description = models.TextField(blank=True, verbose_name="Description / Indications")
    est_essentiel = models.BooleanField(default=True, verbose_name="Médicament essentiel (LNME)")

    class Meta:
        ordering = ["dci", "nom"]
        verbose_name = "Médicament de référence"
        verbose_name_plural = "Catalogue des médicaments"

    def __str__(self):
        detail = []
        if self.dosage:
            detail.append(self.dosage)
        if self.forme_pharmaceutique:
            detail.append(self.forme_pharmaceutique)
        suffixe = f" ({' - '.join(detail)})" if detail else ""
        return f"{self.nom or self.dci}{suffixe}"

    def save(self, *args, **kwargs):
        # Synchronisation de rétrocompatibilité
        if not self.nom and self.dci:
            self.nom = self.dci.title()
        if self.dci and not self.code_dci:
            self.code_dci = self.dci
        if not self.forme_dosage:
            fd_parts = [p for p in [self.forme_pharmaceutique, self.dosage] if p]
            self.forme_dosage = " - ".join(fd_parts)

        # Construction de l'index de recherche normalisé
        elements = [
            self.nom or "",
            self.dci or "",
            self.dosage or "",
            self.forme_pharmaceutique or "",
            self.categorie_therapeutique or "",
        ]
        self.nom_normalise = normaliser_chaine(" ".join(elements))
        super().save(*args, **kwargs)


class DemandeDisponibilite(models.Model):
    """
    Permet à un patient d'envoyer une demande de vérification de disponibilité
    à une pharmacie lorsqu'aucun inventaire temps-réel n'est confirmé.
    """
    STATUT_CHOICES = [
        ("en_attente", "En attente"),
        ("repondu", "Répondu par la pharmacie"),
        ("annule", "Annulé"),
    ]

    medicament = models.ForeignKey(Medicament, on_delete=models.CASCADE, related_name="demandes_disponibilite")
    pharmacie = models.ForeignKey("pharmacies.Pharmacie", on_delete=models.CASCADE, related_name="demandes_disponibilite")
    nom_patient = models.CharField(max_length=150, blank=True, verbose_name="Nom du patient")
    telephone_patient = models.CharField(max_length=50, verbose_name="Téléphone pour rappel")
    ordonnance_url = models.URLField(blank=True, verbose_name="Photo de l'ordonnance (optionnel)")
    message = models.TextField(blank=True, verbose_name="Message complémentaire")
    statut = models.CharField(max_length=30, choices=STATUT_CHOICES, default="en_attente")
    date_creation = models.DateTimeField(auto_now_add=True)
    date_reponse = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-date_creation"]
        verbose_name = "Demande de disponibilité"
        verbose_name_plural = "Demandes de disponibilité"

    def __str__(self):
        return f"Demande #{self.id} : {self.medicament.nom} -> {self.pharmacie.nom}"
