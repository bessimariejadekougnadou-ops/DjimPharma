from django.urls import path
from .v1_views import (
    PhariviaVersionAPIView,
    PhariviaPharmacieAPIView,
    PhariviaStockAPIView,
)

urlpatterns = [
    # Endpoints officiels conformes à la spécification Pharivia
    path("version", PhariviaVersionAPIView.as_view(), name="pharivia-version"),
    path("version/", PhariviaVersionAPIView.as_view(), name="pharivia-version-slash"),
    path("pharmacie", PhariviaPharmacieAPIView.as_view(), name="pharivia-pharmacie"),
    path("pharmacie/", PhariviaPharmacieAPIView.as_view(), name="pharivia-pharmacie-slash"),
    path("stock", PhariviaStockAPIView.as_view(), name="pharivia-stock"),
    path("stock/", PhariviaStockAPIView.as_view(), name="pharivia-stock-slash"),
]
