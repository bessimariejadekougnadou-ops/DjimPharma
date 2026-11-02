from django.urls import path

from .views import (
    CreerUrgenceAPIView,
    ListeUrgencesAPIView,
    ListeUrgencesPharmacienAPIView,
    TraiterUrgencePharmacienAPIView,
)


urlpatterns = [
    path("urgences/", ListeUrgencesAPIView.as_view()),
    path("urgences/creer/", CreerUrgenceAPIView.as_view()),
    path("pharmacien/urgences/", ListeUrgencesPharmacienAPIView.as_view()),
    path(
        "pharmacien/urgences/<int:pk>/traiter/",
        TraiterUrgencePharmacienAPIView.as_view(),
    ),
]
