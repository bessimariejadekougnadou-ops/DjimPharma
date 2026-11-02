from datetime import timedelta
from django.contrib.auth.models import User
from django.core.exceptions import ValidationError
from django.test import Client, TestCase
from django.utils import timezone

from pharmacies.models import HistoriqueGarde, PeriodeGarde, Pharmacie
from pharmacies.services.garde_service import GardeService
from pharmacies.services.google_places_service import GooglePlacesService


class TestPharmacieEtGardeDynamique(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="dr_koffi", password="password123")
        self.pharmacie = Pharmacie.objects.create(
            nom="Pharmacie de la Paix",
            adresse="Boulevard du 13 Janvier, Lomé",
            ville="Lomé",
            telephone="+228 22 21 00 11",
            identifiant_as_pharm="onpt_paix_001",
            latitude=6.1319,
            longitude=1.2228,
            est_active=True,
            statut_verification="verifiee_officielle",
            source_verification="ONPT Togo",
        )

    def test_garde_inactive_par_defaut_sans_periode(self):
        """Une pharmacie sans période validée ne doit jamais être affichée de garde."""
        self.assertFalse(self.pharmacie.est_de_garde)
        self.assertIsNone(self.pharmacie.periode_garde_active())

    def test_validation_dates_incoherentes(self):
        """La date de fin doit obligatoirement être postérieure à la date de début."""
        maintenant = timezone.now()
        with self.assertRaises(ValidationError):
            GardeService.publier_periode_garde(
                pharmacie=self.pharmacie,
                date_debut=maintenant,
                date_fin=maintenant - timedelta(hours=2),
                zone="Lomé Centre",
                user=self.user,
            )

    def test_activation_garde_dynamique(self):
        """La publication d'une garde valide active immédiatement le statut."""
        maintenant = timezone.now()
        debut = maintenant - timedelta(hours=1)
        fin = maintenant + timedelta(days=2)

        periode = GardeService.publier_periode_garde(
            pharmacie=self.pharmacie,
            date_debut=debut,
            date_fin=fin,
            zone="Lomé Centre - Zone 1",
            source="Tableau officiel ONPT Togo - Semaine 42",
            user=self.user,
        )

        self.pharmacie.refresh_from_db()
        self.assertTrue(self.pharmacie.est_de_garde)
        self.assertEqual(self.pharmacie.periode_garde_active().id, periode.id)

        # Vérification de l'historique d'audit
        self.assertTrue(
            HistoriqueGarde.objects.filter(
                pharmacie=self.pharmacie,
                action="VALIDATION",
            ).exists()
        )

    def test_expiration_automatique_garde(self):
        """Une garde dont la date de fin est passée doit être désactivée automatiquement."""
        maintenant = timezone.now()
        debut = maintenant - timedelta(days=5)
        fin = maintenant - timedelta(hours=1)  # Déjà terminée

        PeriodeGarde.objects.create(
            pharmacie=self.pharmacie,
            date_debut=debut,
            date_fin=fin,
            zone="Lomé Centre",
            statut_validation="valide",
        )

        # Recalcul planifié
        rapport = GardeService.verifier_et_actualiser_toutes_les_gardes()
        self.pharmacie.refresh_from_db()

        self.assertFalse(self.pharmacie.est_de_garde)
        self.assertGreaterEqual(rapport["gardes_expirees"], 1)


class TestGooglePlacesService(TestCase):
    def setUp(self):
        self.service = GooglePlacesService()
        self.pharmacie = Pharmacie.objects.create(
            nom="Pharmacie Tokoin Hôpital",
            adresse="Avenue de la Libération, Lomé",
            ville="Lomé",
            telephone="+228 22 21 44 55",
            identifiant_as_pharm="onpt_tokoin_hosp",
            latitude=6.1365,
            longitude=1.2185,
        )

    def test_recherche_sans_cle_utilise_base_locale_explicite(self):
        """En l'absence de clé Google Places, le système renvoie la base officielle avec message explicite."""
        res = self.service.search_pharmacies(query="Tokoin", ville="Lomé")
        self.assertIn("source", res)
        self.assertIn("base_locale_onpt", res["source"])
        self.assertGreaterEqual(res["total"], 1)
        self.assertEqual(res["resultats"][0]["nom"], "Pharmacie Tokoin Hôpital")


class TestApiEndpoints(TestCase):
    def setUp(self):
        self.client = Client()
        self.pharmacie = Pharmacie.objects.create(
            nom="Pharmacie du 2 Février",
            adresse="Place de l'Indépendance, Lomé",
            ville="Lomé",
            telephone="+228 22 22 33 44",
            identifiant_as_pharm="onpt_fevrier_001",
            latitude=6.1280,
            longitude=1.2160,
        )

    def test_endpoint_liste_pharmacies(self):
        res = self.client.get("/api/pharmacies/")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIsInstance(data, list)
        self.assertGreaterEqual(len(data), 1)
        # Vérification des coordonnées GPS incluses
        item = next(p for p in data if p["id"] == self.pharmacie.id)
        self.assertEqual(item["latitude"], 6.1280)
        self.assertEqual(item["longitude"], 1.2160)

    def test_endpoint_statistiques_gardes(self):
        res = self.client.get("/api/pharmacies/gardes/statistiques/")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("total_gardes_actives", data)
        self.assertIn("repartition_par_ville", data)

    def test_endpoint_actualiser_gardes(self):
        res = self.client.post("/api/pharmacies/gardes/actualiser/")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("total_gardes_actives", data)
