from django.contrib.auth import logout
from rest_framework import generics, status
from rest_framework.authtoken.models import Token
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from .models import SessionUtilisateur
from .serializers import (
    ChangementMotDePasseSerializer,
    ConnexionSerializer,
    InscriptionSerializer,
    ProfilUtilisateurSerializer,
    SessionUtilisateurSerializer,
)


class InscriptionAPIView(generics.CreateAPIView):
    serializer_class = InscriptionSerializer
    permission_classes = [AllowAny]


class ConnexionAPIView(generics.GenericAPIView):
    serializer_class = ConnexionSerializer
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        compte = serializer.validated_data["compte"]
        token, _ = Token.objects.get_or_create(user=compte)
        if hasattr(compte, "profil"):
            utilisateur = compte.profil
            role = utilisateur.role
            utilisateur_id = utilisateur.id
            nom = utilisateur.nom
            prenom = utilisateur.prenom
            email = utilisateur.email
        elif hasattr(compte, "profil_pharmacien"):
            profil = compte.profil_pharmacien
            role = "pharmacien"
            utilisateur_id = profil.id
            nom = compte.last_name
            prenom = compte.first_name
            email = compte.email
        else:
            profil = compte.profil_livreur
            role = "livreur"
            utilisateur_id = profil.id
            nom = compte.last_name
            prenom = compte.first_name
            email = compte.email

        from django.utils import timezone
        SessionUtilisateur.objects.update_or_create(
            token=token.key,
            defaults={
                "user": compte,
                "device_name": request.META.get("HTTP_USER_AGENT", "")[:100],
                "ip_address": request.META.get("REMOTE_ADDR", ""),
                "user_agent": request.META.get("HTTP_USER_AGENT", ""),
                "statut": "active",
                "date_derniere_activite": timezone.now(),
            },
        )

        return Response(
            {
                "token": token.key,
                "utilisateur": {
                    "id": utilisateur_id,
                    "nom": nom,
                    "prenom": prenom,
                    "email": email,
                    "role": role,
                },
            },
            status=status.HTTP_200_OK,
        )


class ProfilUtilisateurAPIView(generics.RetrieveUpdateAPIView):
    serializer_class = ProfilUtilisateurSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_object(self):
        return self.request.user.profil


class ChangementMotDePasseAPIView(generics.GenericAPIView):
    serializer_class = ChangementMotDePasseSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = self.get_serializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)

        user = request.user
        user.set_password(serializer.validated_data["nouveau_mot_de_passe"])
        user.save()

        return Response(
            {"message": "Mot de passe mis a jour avec succes."},
            status=status.HTTP_200_OK,
        )


class DeconnexionAPIView(generics.GenericAPIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def post(self, request):
        token = request.auth
        if token is not None:
            token.delete()
        logout(request)

        return Response(
            {"message": "Deconnexion reussie."},
            status=status.HTTP_200_OK,
        )


class SessionUtilisateurListAPIView(generics.ListAPIView):
    serializer_class = SessionUtilisateurSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return SessionUtilisateur.objects.filter(user=self.request.user).order_by("-date_connexion")
