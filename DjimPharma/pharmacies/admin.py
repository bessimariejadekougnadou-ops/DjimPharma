from django.contrib import admin
from .models import HistoriqueGarde, PeriodeGarde, Pharmacie


@admin.register(Pharmacie)
class PharmacieAdmin(admin.ModelAdmin):
    list_display = (
        "nom",
        "ville",
        "quartier",
        "telephone",
        "est_de_garde",
        "statut_verification",
        "source_donnees",
        "date_derniere_synchro",
    )
    list_filter = ("est_de_garde", "ville", "statut_verification", "source_donnees", "est_active")
    search_fields = ("nom", "adresse", "ville", "quartier", "identifiant_as_pharm", "google_place_id")
    actions = ["actualiser_gardes_action"]

    @admin.action(description="Recalculer le statut de garde des pharmacies sélectionnées")
    def actualiser_gardes_action(self, request, queryset):
        for p in queryset:
            p.actualiser_statut_garde()
        self.message_user(request, f"{queryset.count()} pharmacies actualisées.")


@admin.register(PeriodeGarde)
class PeriodeGardeAdmin(admin.ModelAdmin):
    list_display = (
        "pharmacie",
        "zone",
        "date_debut",
        "date_fin",
        "statut_validation",
        "source",
        "valide_par",
    )
    list_filter = ("statut_validation", "zone", "pharmacie__ville")
    search_fields = ("pharmacie__nom", "zone", "source", "commentaire")
    date_hierarchy = "date_debut"


@admin.register(HistoriqueGarde)
class HistoriqueGardeAdmin(admin.ModelAdmin):
    list_display = ("action", "pharmacie", "modifie_par", "date_action")
    list_filter = ("action", "date_action")
    search_fields = ("pharmacie__nom", "action")
