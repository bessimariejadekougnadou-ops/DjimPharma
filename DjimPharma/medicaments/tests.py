from django.test import TestCase, Client
from django.urls import reverse
from medicaments.models import Medicament, DemandeDisponibilite, normaliser_chaine
from pharmacies.models import Pharmacie


class MedicamentCatalogueTestCase(TestCase):
    def setUp(self):
        self.client = Client()
        self.pharmacie = Pharmacie.objects.create(
            nom="Pharmacie de Test Lomé",
            adresse="Boulevard du 13 Janvier",
            ville="Lomé",
            telephone="+228 22 21 00 00",
            est_de_garde=True,
            latitude=6.1375,
            longitude=1.2125,
        )
        self.med1 = Medicament.objects.create(
            nom="Paracétamol 500mg (Comprimé)",
            dci="Paracétamol",
            dosage="500mg",
            forme_pharmaceutique="Comprimé",
            categorie_therapeutique="2. ANALGESIQUES, ANTIPYRETIQUES",
            statut_reglementaire="liste_essentielle_togo",
            source_information="Arrêté N° 147/2021/MSHPAUS - LNME Togo",
            est_actif=True,
        )
        self.med2 = Medicament.objects.create(
            nom="Amoxicilline 500mg (Gélule)",
            dci="Amoxicilline",
            dosage="500mg",
            forme_pharmaceutique="Gélule",
            categorie_therapeutique="6.2 ANTIBACTERIENS",
            statut_reglementaire="liste_essentielle_togo",
            source_information="Arrêté N° 147/2021/MSHPAUS - LNME Togo",
            est_actif=True,
        )

    def test_normalisation_chaine_sans_accents(self):
        """Vérifie que la normalisation supprime accents, majuscules et espaces superflus."""
        self.assertEqual(normaliser_chaine("Paracétamol"), "paracetamol")
        self.assertEqual(normaliser_chaine("AMOXICILLINE 500MG"), "amoxicilline 500mg")
        self.assertEqual(normaliser_chaine("Éphédrine  chlorhydrate"), "ephedrine chlorhydrate")

    def test_recherche_insensible_aux_accents_et_casse(self):
        """Vérifie que l'API de recherche trouve les médicaments avec ou sans accents."""
        # Avec accent
        resp1 = self.client.get("/api/medicaments/?q=paracétamol")
        self.assertEqual(resp1.status_code, 200)
        self.assertEqual(resp1.json()["count"], 1)

        # Sans accent et majuscule
        resp2 = self.client.get("/api/medicaments/?q=PARACETAMOL")
        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(resp2.json()["count"], 1)

        # Recherche multi-mots : nom + dosage
        resp3 = self.client.get("/api/medicaments/?q=amoxicilline 500")
        self.assertEqual(resp3.status_code, 200)
        self.assertEqual(resp3.json()["count"], 1)

    def test_transparence_disponibilite_stricte(self):
        """Vérifie qu'aucun médicament n'est faussement prétendu en stock."""
        resp = self.client.get(f"/api/medicaments/{self.med1.id}/")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["disponibilite_statut"], "non_confirmee")
        self.assertEqual(data["disponibilite_libelle"], "Disponibilité non confirmée")
        self.assertIn("Aucun stock en temps réel", data["disponibilite_message"])
        self.assertTrue(data["peut_contacter_pharmacie"])
        # Vérifie que les pharmacies de garde sont proposées pour contact
        self.assertGreaterEqual(len(data.get("pharmacies_contact_recommandees", [])), 1)

    def test_statut_reglementaire_ne_pretend_pas_amm(self):
        """Vérifie que le statut réglementaire reste liste essentielle Togo et non fausse AMM."""
        self.assertEqual(self.med1.statut_reglementaire, "liste_essentielle_togo")
        self.assertNotEqual(self.med1.statut_reglementaire, "amm_validee")

    def test_creation_demande_disponibilite(self):
        """Vérifie qu'un patient peut envoyer une demande de confirmation à une pharmacie."""
        payload = {
            "medicament": self.med1.id,
            "pharmacie": self.pharmacie.id,
            "nom_patient": "Koffi Mensah",
            "telephone_patient": "+228 90 00 00 00",
            "message": "Bonjour, avez-vous ce médicament en stock svp ?",
        }
        resp = self.client.post("/api/medicaments/demandes-disponibilite/", payload, content_type="application/json")
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(DemandeDisponibilite.objects.count(), 1)
        demande = DemandeDisponibilite.objects.first()
        self.assertEqual(demande.nom_patient, "Koffi Mensah")
        self.assertEqual(demande.statut, "en_attente")
