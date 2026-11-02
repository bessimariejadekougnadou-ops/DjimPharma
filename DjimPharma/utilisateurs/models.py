from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone


class Utilisateur(models.Model):
    ROLE_CHOIX = [
        ("client", "Client"),
        ("pharmacien", "Pharmacien"),
        ("livreur", "Livreur"),
        ("admin", "Admin DjimPharma"),
    ]

    compte = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="profil",
        null=True,
        blank=True,
    )
    nom = models.CharField(max_length=100)
    prenom = models.CharField(max_length=100)
    email = models.EmailField(unique=True)
    role = models.CharField(max_length=20, choices=ROLE_CHOIX, default="client")
    telephone = models.CharField(max_length=20, blank=True)
    adresse_principale = models.CharField(max_length=255, blank=True)
    ville = models.CharField(max_length=100, blank=True)
    quartier = models.CharField(max_length=100, blank=True)
    langue_preferee = models.CharField(max_length=10, default="fr")
    est_actif = models.BooleanField(default=True)

    def __str__(self):
        return f"{self.prenom} {self.nom}"


class PharmacienProfile(models.Model):
    compte = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="profil_pharmacien",
    )
    pharmacie = models.ForeignKey(
        "pharmacies.Pharmacie",
        on_delete=models.CASCADE,
        related_name="pharmaciens",
    )
    telephone = models.CharField(max_length=20, blank=True)

    def __str__(self):
        return f"Pharmacien {self.compte.get_full_name() or self.compte.username}"


class LivreurProfile(models.Model):
    STATUT_CHOIX = [
        ("disponible", "Disponible"),
        ("en_livraison", "En livraison"),
        ("indisponible", "Indisponible"),
    ]

    compte = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="profil_livreur",
    )
    telephone = models.CharField(max_length=20, blank=True)
    immatriculation_vehicule = models.CharField(max_length=50, blank=True)
    est_disponible = models.BooleanField(default=True)
    statut_actuel = models.CharField(
        max_length=20,
        choices=STATUT_CHOIX,
        default="disponible",
    )

    def __str__(self):
        return f"Livreur {self.compte.get_full_name() or self.compte.username}"


class SessionUtilisateur(models.Model):
    STATUT_CHOIX = [
        ("active", "Active"),
        ("deconnectee", "Déconnectée"),
        ("expiree", "Expirée"),
    ]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="sessions_djimpharma",
    )
    token = models.CharField(max_length=255, unique=True)
    device_name = models.CharField(max_length=100, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True)
    statut = models.CharField(max_length=20, choices=STATUT_CHOIX, default="active")
    date_connexion = models.DateTimeField(default=timezone.now)
    date_derniere_activite = models.DateTimeField(default=timezone.now)
    date_deconnexion = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.user.email} - {self.statut}"


class HistoriqueMotDePasse(models.Model):
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="historique_mdp",
    )
    mot_de_passe_hash = models.CharField(max_length=255)
    date_changement = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.user.email} - {self.date_changement}"


class EmailVerificationToken(models.Model):
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="email_tokens",
    )
    code = models.CharField(max_length=10)
    date_creation = models.DateTimeField(auto_now_add=True)
    date_expiration = models.DateTimeField()
    est_utilise = models.BooleanField(default=False)

    def __str__(self):
        return f"{self.user.email} - {self.code}"
