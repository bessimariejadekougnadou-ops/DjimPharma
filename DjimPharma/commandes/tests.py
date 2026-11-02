from decimal import Decimal

from django.contrib.auth.models import User
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from medicaments.models import Medicament
from pharmacies.models import Pharmacie
from stocks.models import StockPharmacie
from utilisateurs.models import PharmacienProfile, Utilisateur

from .models import Commande


class CommandeAPITests(APITestCase):
    def setUp(self):
        compte = User.objects.create_user(
            username="client@example.com",
            email="client@example.com",
            password="motdepasse-solide",
        )
        self.utilisateur = Utilisateur.objects.create(
            compte=compte,
            nom="Camara",
            prenom="Moussa",
            email="client@example.com",
        )
        self.token = Token.objects.create(user=compte)
        self.pharmacie = Pharmacie.objects.create(
            nom="Pharmacie de la Paix",
            adresse="5 avenue de la Paix",
            ville="Conakry",
            identifiant_as_pharm="PHARM-002",
        )
        self.medicament = Medicament.objects.create(nom="Amoxicilline 500 mg")
        self.stock = StockPharmacie.objects.create(
            pharmacie=self.pharmacie,
            medicament=self.medicament,
            quantite=5,
            est_disponible=True,
            prix=Decimal("4500.00"),
        )

    def authentifier_client(self):
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def donnees_commande(self, quantite):
        return {
            "pharmacie": self.pharmacie.id,
            "mode_reception": "retrait",
            "lignes": [{"medicament": self.medicament.id, "quantite": quantite}],
        }

    def test_creation_commande_diminue_le_stock(self):
        self.authentifier_client()

        response = self.client.post(
            "/api/commandes/creer/", self.donnees_commande(3), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Commande.objects.count(), 1)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantite, 2)
        self.assertTrue(self.stock.est_disponible)

    def test_commande_stock_insuffisant_est_refusee(self):
        self.authentifier_client()

        response = self.client.post(
            "/api/commandes/creer/", self.donnees_commande(6), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Commande.objects.count(), 0)
        self.stock.refresh_from_db()
        self.assertEqual(self.stock.quantite, 5)

    def test_liste_commandes_exige_une_authentification(self):
        response = self.client.get("/api/commandes/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_pharmacien_peut_modifier_le_statut_de_sa_commande(self):
        commande = Commande.objects.create(
            utilisateur=self.utilisateur,
            pharmacie=self.pharmacie,
            mode_reception="retrait",
        )
        compte_pharmacien = User.objects.create_user(
            username="pharmacien@example.com",
            password="motdepasse-solide",
        )
        PharmacienProfile.objects.create(
            compte=compte_pharmacien,
            pharmacie=self.pharmacie,
        )
        token_pharmacien = Token.objects.create(user=compte_pharmacien)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token_pharmacien.key}")

        response = self.client.patch(
            f"/api/pharmacien/commandes/{commande.id}/statut/",
            {"statut": "en_preparation"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        commande.refresh_from_db()
        self.assertEqual(commande.statut, "en_preparation")
