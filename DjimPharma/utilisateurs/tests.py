from django.contrib.auth.models import User
from rest_framework import status
from rest_framework.test import APITestCase

from .models import Utilisateur


class AuthentificationAPITests(APITestCase):
    def test_inscription_puis_connexion_retourne_un_jeton(self):
        inscription = self.client.post(
            "/api/inscription/",
            {
                "nom": "Diallo",
                "prenom": "Aminata",
                "email": "aminata@example.com",
                "mot_de_passe": "motdepasse-solide",
            },
            format="json",
        )

        self.assertEqual(inscription.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(username="aminata@example.com").exists())
        self.assertTrue(Utilisateur.objects.filter(email="aminata@example.com").exists())

        connexion = self.client.post(
            "/api/connexion/",
            {"email": "aminata@example.com", "mot_de_passe": "motdepasse-solide"},
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK)
        self.assertIn("token", connexion.data)
        self.assertEqual(connexion.data["utilisateur"]["email"], "aminata@example.com")

    def test_changement_de_mot_de_passe(self):
        self.client.post(
            "/api/inscription/",
            {
                "nom": "Kouassi",
                "prenom": "Jean",
                "email": "jean@example.com",
                "mot_de_passe": "motdepasse-solide",
            },
            format="json",
        )

        connexion = self.client.post(
            "/api/connexion/",
            {"email": "jean@example.com", "mot_de_passe": "motdepasse-solide"},
            format="json",
        )
        token = connexion.data["token"]

        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
        reponse = self.client.post(
            "/api/mot-de-passe/changer/",
            {
                "ancien_mot_de_passe": "motdepasse-solide",
                "nouveau_mot_de_passe": "nouveau-mot-de-passe",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["message"], "Mot de passe mis a jour avec succes.")
