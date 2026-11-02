from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated

from .models import StockPharmacie
from utilisateurs.permissions import IsPharmacien

from .serializers import GestionStockPharmacienSerializer, StockPharmacieSerializer


class ListeStocksAPIView(generics.ListAPIView):
    serializer_class = StockPharmacieSerializer

    def get_queryset(self):
        stocks = StockPharmacie.objects.filter(
            est_disponible=True,
            quantite__gt=0,
        ).select_related("pharmacie", "medicament")

        recherche = self.request.query_params.get("recherche", "").strip()
        ville = self.request.query_params.get("ville", "").strip()
        pharmacie_id = self.request.query_params.get("pharmacie", "").strip()

        if recherche:
            stocks = stocks.filter(medicament__nom__icontains=recherche)

        if ville:
            stocks = stocks.filter(pharmacie__ville__icontains=ville)

        if pharmacie_id.isdigit():
            stocks = stocks.filter(pharmacie_id=pharmacie_id)

        return stocks.order_by("medicament__nom", "pharmacie__nom")


class RechercheMedicamentsAPIView(ListeStocksAPIView):
    pass


class GestionStocksPharmacienAPIView(generics.ListCreateAPIView):
    serializer_class = GestionStockPharmacienSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return StockPharmacie.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("medicament")

    def perform_create(self, serializer):
        serializer.save(pharmacie=self.request.user.profil_pharmacien.pharmacie)


class DetailStockPharmacienAPIView(generics.RetrieveUpdateAPIView):
    serializer_class = GestionStockPharmacienSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return StockPharmacie.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("medicament")
