from rest_framework import generics, status
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification, PreferenceNotificationGarde
from .serializers import (
    NotificationLueSerializer,
    NotificationSerializer,
    PreferenceNotificationGardeSerializer,
)


class ListeNotificationsAPIView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, "profil"):
            return Notification.objects.filter(utilisateur=user.profil)
        return Notification.objects.none()


class LireNotificationAPIView(generics.UpdateAPIView):
    serializer_class = NotificationLueSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, "profil"):
            return Notification.objects.filter(utilisateur=user.profil)
        return Notification.objects.none()


class PreferencesGardeAPIView(APIView):
    """
    Permet à un utilisateur de consulter et modifier ses préférences de notifications de garde
    (ville, zone, rayon, activation des alertes et token push).
    """

    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not hasattr(request.user, "profil"):
            return Response({"erreur": "Profil utilisateur introuvable."}, status=status.HTTP_400_BAD_REQUEST)

        pref, _ = PreferenceNotificationGarde.objects.get_or_create(
            utilisateur=request.user.profil,
            defaults={"ville": request.user.profil.ville or "Lomé"},
        )
        return Response(PreferenceNotificationGardeSerializer(pref).data)

    def put(self, request):
        if not hasattr(request.user, "profil"):
            return Response({"erreur": "Profil utilisateur introuvable."}, status=status.HTTP_400_BAD_REQUEST)

        pref, _ = PreferenceNotificationGarde.objects.get_or_create(
            utilisateur=request.user.profil,
            defaults={"ville": request.user.profil.ville or "Lomé"},
        )
        serializer = PreferenceNotificationGardeSerializer(pref, data=request.data, partial=True)
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
