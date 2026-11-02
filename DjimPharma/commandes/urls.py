from django.urls import path

from .views import (
    CreerCommandeAPIView,
    ListeCommandesAPIView,
    ListeCommandesLivreurAPIView,
    ListeCommandesPharmacienAPIView,
    ModifierStatutCommandeLivreurAPIView,
    ModifierStatutCommandePharmacienAPIView,
)


urlpatterns = [
    path("commandes/", ListeCommandesAPIView.as_view()),
    path("commandes/creer/", CreerCommandeAPIView.as_view()),
    path("pharmacien/commandes/", ListeCommandesPharmacienAPIView.as_view()),
    path(
        "pharmacien/commandes/<int:pk>/statut/",
        ModifierStatutCommandePharmacienAPIView.as_view(),
    ),
    path("livreur/commandes/", ListeCommandesLivreurAPIView.as_view()),
    path(
        "livreur/commandes/<int:pk>/statut/",
        ModifierStatutCommandeLivreurAPIView.as_view(),
    ),
]
