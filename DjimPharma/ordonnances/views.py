from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone

from .models import Ordonnance
from notifications.models import Notification
from utilisateurs.permissions import IsClient, IsPharmacien

from .serializers import OrdonnanceSerializer, TraitementOrdonnanceSerializer


class ListeOrdonnancesAPIView(generics.ListAPIView):
    serializer_class = OrdonnanceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsClient]

    def get_queryset(self):
        return Ordonnance.objects.filter(utilisateur=self.request.user.profil).select_related(
            "pharmacie"
        )


class CreerOrdonnanceAPIView(generics.CreateAPIView):
    serializer_class = OrdonnanceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsClient]

    def perform_create(self, serializer):
        serializer.save(utilisateur=self.request.user.profil)


class ListeOrdonnancesPharmacienAPIView(generics.ListAPIView):
    serializer_class = OrdonnanceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return Ordonnance.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("utilisateur", "pharmacie").order_by("-date_envoi")


class TraiterOrdonnancePharmacienAPIView(generics.UpdateAPIView):
    serializer_class = TraitementOrdonnanceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return Ordonnance.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("utilisateur")

    def perform_update(self, serializer):
        ordonnance = serializer.save(date_traitement=timezone.now())
        Notification.objects.create(
            utilisateur=ordonnance.utilisateur,
            titre="Ordonnance mise a jour",
            message=f"Votre ordonnance est {ordonnance.get_statut_display().lower()}.",
            type_notification="ordonnance",
        )
