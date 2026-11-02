from django.urls import path
from .views import (
    ActualiserGardesAPIView,
    HistoriqueGardesAPIView,
    ImporterGardesAPIView,
    ListeGardesAPIView,
    ListePharmaciesAPIView,
    PublierGardeAPIView,
    RechercheDynamiquePharmaciesAPIView,
    StatistiquesGardesAPIView,
)

urlpatterns = [
    path("pharmacies/", ListePharmaciesAPIView.as_view(), name="liste_pharmacies"),
    path("pharmacies/recherche-dynamique/", RechercheDynamiquePharmaciesAPIView.as_view(), name="recherche_dynamique_pharmacies"),
    path("pharmacies/gardes/", ListeGardesAPIView.as_view(), name="liste_gardes"),
    path("pharmacies/gardes/publier/", PublierGardeAPIView.as_view(), name="publier_garde"),
    path("pharmacies/gardes/importer/", ImporterGardesAPIView.as_view(), name="importer_gardes"),
    path("pharmacies/gardes/actualiser/", ActualiserGardesAPIView.as_view(), name="actualiser_gardes"),
    path("pharmacies/gardes/statistiques/", StatistiquesGardesAPIView.as_view(), name="statistiques_gardes"),
    path("pharmacies/gardes/historique/", HistoriqueGardesAPIView.as_view(), name="historique_gardes"),
]
