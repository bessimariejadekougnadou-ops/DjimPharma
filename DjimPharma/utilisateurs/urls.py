from django.urls import path

from .views import (
    ChangementMotDePasseAPIView,
    ConnexionAPIView,
    DeconnexionAPIView,
    InscriptionAPIView,
    ProfilUtilisateurAPIView,
    SessionUtilisateurListAPIView,
)


urlpatterns = [
    path("inscription/", InscriptionAPIView.as_view(), name="inscription"),
    path("connexion/", ConnexionAPIView.as_view(), name="connexion"),
    path("deconnexion/", DeconnexionAPIView.as_view(), name="deconnexion"),
    path("profil/", ProfilUtilisateurAPIView.as_view(), name="profil"),
    path(
        "mot-de-passe/changer/",
        ChangementMotDePasseAPIView.as_view(),
        name="changer-mot-de-passe",
    ),
    path("sessions/", SessionUtilisateurListAPIView.as_view(), name="sessions"),
]
