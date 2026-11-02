import uuid

from django.db import models
from django.core.exceptions import ValidationError

from medicaments.models import Medicament
from pharmacies.models import Pharmacie
from stocks.models import StockPharmacie
from utilisateurs.models import Utilisateur


class Commande(models.Model):
    STATUT_CHOIX = [
        ("en_attente", "En attente"),
        ("en_preparation", "En preparation"),
        ("prete", "Prete"),
        ("livree", "Livree"),
        ("annulee", "Annulee"),
    ]

    MODE_RECEPTION_CHOIX = [
        ("retrait", "Retrait en pharmacie"),
        ("livraison", "Livraison a domicile"),
    ]

    MODE_PAIEMENT_CHOIX = [
        ("paiement_livraison", "Paiement a la livraison"),
        ("mobile_money", "Mobile money"),
        ("carte", "Carte bancaire"),
    ]

    STATUT_PAIEMENT_CHOIX = [
        ("en_attente", "En attente"),
        ("paye", "Paye"),
        ("echec", "Echec"),
    ]

    reference = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    utilisateur = models.ForeignKey(Utilisateur, on_delete=models.CASCADE)
    pharmacie = models.ForeignKey(Pharmacie, on_delete=models.CASCADE)
    livreur = models.ForeignKey(
        "utilisateurs.LivreurProfile",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="commandes",
    )
    date_commande = models.DateTimeField(auto_now_add=True)
    statut = models.CharField(
        max_length=20,
        choices=STATUT_CHOIX,
        default="en_attente",
    )
    mode_reception = models.CharField(
        max_length=20,
        choices=MODE_RECEPTION_CHOIX,
        default="retrait",
    )
    adresse_livraison = models.CharField(max_length=255, blank=True)
    montant_total = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    mode_paiement = models.CharField(
        max_length=30,
        choices=MODE_PAIEMENT_CHOIX,
        default="paiement_livraison",
    )
    statut_paiement = models.CharField(
        max_length=20,
        choices=STATUT_PAIEMENT_CHOIX,
        default="en_attente",
    )

    def __str__(self):
        return f"Commande {self.id} - {self.utilisateur.prenom} {self.utilisateur.nom}"


class LigneCommande(models.Model):
    commande = models.ForeignKey(Commande, on_delete=models.CASCADE)
    medicament = models.ForeignKey(Medicament, on_delete=models.CASCADE)
    quantite = models.PositiveIntegerField(default=1)
    prix_unitaire = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=0,
        blank=True,
    )

    def __str__(self):
        return f"{self.medicament.nom} x {self.quantite}"

    def save(self, *args, **kwargs):
        stock = StockPharmacie.objects.filter(
            pharmacie=self.commande.pharmacie,
            medicament=self.medicament,
        ).first()

        if stock is None:
            raise ValidationError(
                "Aucun stock trouve pour ce medicament dans la pharmacie de la commande."
            )

        self.prix_unitaire = stock.prix
        super().save(*args, **kwargs)
