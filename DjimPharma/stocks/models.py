from django.db import models

from medicaments.models import Medicament
from pharmacies.models import Pharmacie


class StockPharmacie(models.Model):
    pharmacie = models.ForeignKey(Pharmacie, on_delete=models.CASCADE, related_name="stocks")
    medicament = models.ForeignKey(Medicament, on_delete=models.CASCADE, related_name="stocks")
    code_externe = models.CharField(max_length=100, blank=True, default="", db_index=True, verbose_name="Code externe / Réf caisse")
    quantite = models.PositiveIntegerField(default=0)
    est_disponible = models.BooleanField(default=True)
    prix = models.DecimalField(max_digits=10, decimal_places=2)
    derniere_synchronisation = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["pharmacie", "medicament"],
                name="stock_unique_par_pharmacie_et_medicament",
            )
        ]

    def __str__(self):
        return f"{self.medicament.nom} - {self.pharmacie.nom}"
