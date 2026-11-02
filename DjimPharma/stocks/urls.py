from django.urls import path

from .views import (
    DetailStockPharmacienAPIView,
    GestionStocksPharmacienAPIView,
    ListeStocksAPIView,
    RechercheMedicamentsAPIView,
)


urlpatterns = [
    path("stocks/", ListeStocksAPIView.as_view()),
    path("recherche-medicaments/", RechercheMedicamentsAPIView.as_view()),
    path("pharmacien/stocks/", GestionStocksPharmacienAPIView.as_view()),
    path("pharmacien/stocks/<int:pk>/", DetailStockPharmacienAPIView.as_view()),
]
