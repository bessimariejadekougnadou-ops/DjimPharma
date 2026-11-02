from django.urls import path

from .views import (
    CreerOrdonnanceAPIView,
    ListeOrdonnancesAPIView,
    ListeOrdonnancesPharmacienAPIView,
    TraiterOrdonnancePharmacienAPIView,
)


urlpatterns = [
    path("ordonnances/", ListeOrdonnancesAPIView.as_view()),
    path("ordonnances/envoyer/", CreerOrdonnanceAPIView.as_view()),
    path("pharmacien/ordonnances/", ListeOrdonnancesPharmacienAPIView.as_view()),
    path(
        "pharmacien/ordonnances/<int:pk>/traiter/",
        TraiterOrdonnancePharmacienAPIView.as_view(),
    ),
]
