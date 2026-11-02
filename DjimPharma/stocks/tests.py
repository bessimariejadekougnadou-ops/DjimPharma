from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from medicaments.models import Medicament
from pharmacies.models import Pharmacie

from .models import StockPharmacie


class RechercheStocksAPITests(APITestCase):
    def test_recherche_retourne_seulement_le_stock_disponible(self):
        pharmacie = Pharmacie.objects.create(
            nom="Pharmacie Centrale",
            adresse="12 rue du Marche",
            ville="Conakry",
            identifiant_as_pharm="PHARM-001",
        )
        paracetamol = Medicament.objects.create(nom="Paracetamol 500 mg")
        indisponible = Medicament.objects.create(nom="Paracetamol sirop")
        StockPharmacie.objects.create(
            pharmacie=pharmacie,
            medicament=paracetamol,
            quantite=8,
            est_disponible=True,
            prix=Decimal("2500.00"),
        )
        StockPharmacie.objects.create(
            pharmacie=pharmacie,
            medicament=indisponible,
            quantite=0,
            est_disponible=False,
            prix=Decimal("3000.00"),
        )

        response = self.client.get("/api/recherche-medicaments/?recherche=paracetamol")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]["medicament"], paracetamol.id)
