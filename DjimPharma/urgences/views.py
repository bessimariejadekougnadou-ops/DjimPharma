from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated

from .models import DemandeUrgence
from notifications.models import Notification
from utilisateurs.permissions import IsClient, IsPharmacien

from .serializers import DemandeUrgenceSerializer, TraitementUrgenceSerializer


class ListeUrgencesAPIView(generics.ListAPIView):
    serializer_class = DemandeUrgenceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsClient]

    def get_queryset(self):
        return DemandeUrgence.objects.filter(utilisateur=self.request.user.profil)


class CreerUrgenceAPIView(generics.CreateAPIView):
    serializer_class = DemandeUrgenceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsClient]

    def perform_create(self, serializer):
        serializer.save(utilisateur=self.request.user.profil)


class ListeUrgencesPharmacienAPIView(generics.ListAPIView):
    serializer_class = DemandeUrgenceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return DemandeUrgence.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("utilisateur", "pharmacie").order_by("-date_demande")


class TraiterUrgencePharmacienAPIView(generics.UpdateAPIView):
    serializer_class = TraitementUrgenceSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return DemandeUrgence.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("utilisateur")

    def perform_update(self, serializer):
        urgence = serializer.save(pharmacien=self.request.user.profil_pharmacien)
        Notification.objects.create(
            utilisateur=urgence.utilisateur,
            titre="Urgence mise a jour",
            message=f"Votre demande est maintenant {urgence.get_statut_display().lower()}.",
            type_notification="urgence",
        )
