from django.contrib import admin

from .models import Commande, LigneCommande


@admin.register(Commande)
class CommandeAdmin(admin.ModelAdmin):
    list_display = ("id", "reference", "pharmacie", "statut", "montant_total")
    list_filter = ("statut", "mode_reception", "statut_paiement")


@admin.register(LigneCommande)
class LigneCommandeAdmin(admin.ModelAdmin):
    readonly_fields = ("prix_unitaire",)
