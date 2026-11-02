from rest_framework import generics
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated

from .models import Commande
from notifications.models import Notification
from utilisateurs.permissions import IsClient, IsLivreur, IsPharmacien

from .serializers import (
    CommandeSerializer,
    CommandeStatutSerializer,
    CreerCommandeSerializer,
    LivraisonStatutSerializer,
)


class ListeCommandesAPIView(generics.ListAPIView):
    serializer_class = CommandeSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsClient]

    def get_queryset(self):
        return (
            Commande.objects.filter(utilisateur=self.request.user.profil)
            .select_related("pharmacie")
            .prefetch_related("lignecommande_set__medicament")
        )


class CreerCommandeAPIView(generics.CreateAPIView):
    serializer_class = CreerCommandeSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsClient]


class ListeCommandesPharmacienAPIView(generics.ListAPIView):
    serializer_class = CommandeSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return (
            Commande.objects.filter(
                pharmacie=self.request.user.profil_pharmacien.pharmacie
            )
            .select_related("utilisateur", "pharmacie", "livreur__compte")
            .prefetch_related("lignecommande_set__medicament")
            .order_by("-date_commande")
        )


class ModifierStatutCommandePharmacienAPIView(generics.UpdateAPIView):
    serializer_class = CommandeStatutSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsPharmacien]

    def get_queryset(self):
        return Commande.objects.filter(
            pharmacie=self.request.user.profil_pharmacien.pharmacie
        ).select_related("utilisateur")

    def perform_update(self, serializer):
        commande = serializer.save()
        Notification.objects.create(
            utilisateur=commande.utilisateur,
            titre="Mise a jour de commande",
            message=f"Votre commande est maintenant {commande.get_statut_display().lower()}.",
            type_notification="commande",
        )


class ListeCommandesLivreurAPIView(generics.ListAPIView):
    serializer_class = CommandeSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsLivreur]

    def get_queryset(self):
        return (
            Commande.objects.filter(livreur=self.request.user.profil_livreur)
            .select_related("utilisateur", "pharmacie", "livreur__compte")
            .prefetch_related("lignecommande_set__medicament")
            .order_by("-date_commande")
        )


class ModifierStatutCommandeLivreurAPIView(generics.UpdateAPIView):
    serializer_class = LivraisonStatutSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated, IsLivreur]

    def get_queryset(self):
        return Commande.objects.filter(
            livreur=self.request.user.profil_livreur
        ).select_related("utilisateur")

    def perform_update(self, serializer):
        commande = serializer.save()
        Notification.objects.create(
            utilisateur=commande.utilisateur,
            titre="Livraison mise a jour",
            message=f"Votre commande est maintenant {commande.get_statut_display().lower()}.",
            type_notification="commande",
        )
