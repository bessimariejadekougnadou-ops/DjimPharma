from django.urls import path
from .views import (
    AsPharmSyncStocksAPIView,
    AsPharmCommandesEnAttenteAPIView,
    AsPharmUpdateCommandeStatutAPIView,
)

from .views import SyncPharmaciesGardeAPIView

urlpatterns = [
    path("integrations/pharmacies-garde/sync/", SyncPharmaciesGardeAPIView.as_view(), name="sync-pharmacies-garde"),
    path("integrations/as-pharm/sync-stocks/", AsPharmSyncStocksAPIView.as_view(), name="as-pharm-sync-stocks"),
    path("integrations/as-pharm/commandes/<str:identifiant_as_pharm>/", AsPharmCommandesEnAttenteAPIView.as_view(), name="as-pharm-commandes-officine"),
    path("integrations/as-pharm/commandes/<uuid:reference>/statut/", AsPharmUpdateCommandeStatutAPIView.as_view(), name="as-pharm-update-commande"),
]
