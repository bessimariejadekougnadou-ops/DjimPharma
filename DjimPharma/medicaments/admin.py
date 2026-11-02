from django.contrib import admin
from .models import Medicament, DemandeDisponibilite


@admin.register(Medicament)
class MedicamentAdmin(admin.ModelAdmin):
    list_display = [
        "dci",
        "forme_pharmaceutique",
        "dosage",
        "categorie_therapeutique",
        "statut_reglementaire",
        "necessite_validation_manuelle",
        "est_actif",
    ]
    list_filter = [
        "statut_reglementaire",
        "necessite_validation_manuelle",
        "est_essentiel",
        "est_actif",
    ]
    search_fields = [
        "nom",
        "dci",
        "nom_normalise",
        "dosage",
        "forme_pharmaceutique",
        "categorie_therapeutique",
    ]
    list_editable = ["est_actif"]
    readonly_fields = ["nom_normalise", "date_importation", "derniere_mise_a_jour"]

    actions = ["valider_selection", "marquer_inactif"]

    @admin.action(description="Valider les médicaments sélectionnés (retirer besoin de validation manuelle)")
    def valider_selection(self, request, queryset):
        queryset.update(necessite_validation_manuelle=False)

    @admin.action(description="Désactiver les médicaments sélectionnés du catalogue")
    def marquer_inactif(self, request, queryset):
        queryset.update(est_actif=False)


@admin.register(DemandeDisponibilite)
class DemandeDisponibiliteAdmin(admin.ModelAdmin):
    list_display = [
        "id",
        "medicament",
        "pharmacie",
        "nom_patient",
        "telephone_patient",
        "statut",
        "date_creation",
    ]
    list_filter = ["statut", "date_creation"]
    search_fields = ["nom_patient", "telephone_patient", "medicament__nom", "pharmacie__nom"]
