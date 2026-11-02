from django.urls import path
from .views import (
    ListeMedicamentsAPIView,
    DetailMedicamentAPIView,
    CategoriesMedicamentsAPIView,
    DemandeDisponibiliteCreateAPIView,
)

urlpatterns = [
    path("medicaments/", ListeMedicamentsAPIView.as_view(), name="liste_medicaments"),
    path("medicaments/<int:pk>/", DetailMedicamentAPIView.as_view(), name="detail_medicament"),
    path("medicaments/categories/", CategoriesMedicamentsAPIView.as_view(), name="categories_medicaments"),
    path("medicaments/demandes-disponibilite/", DemandeDisponibiliteCreateAPIView.as_view(), name="demande_disponibilite"),
]
