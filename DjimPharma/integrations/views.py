from django.utils import timezone
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.permissions import AllowAny

from pharmacies.models import Pharmacie
from medicaments.models import Medicament
from stocks.models import StockPharmacie
from commandes.models import Commande
from notifications.models import Notification

from .models import AsPharmSyncLog
from .serializers import (
    AsPharmSyncPayloadSerializer,
    AsPharmCommandeSerializer,
    AsPharmUpdateCommandeStatutSerializer,
)


class AsPharmSyncStocksAPIView(generics.GenericAPIView):
    """
    Point d'entree pour le connecteur AS-Pharm d'une pharmacie.
    Permet de mettre a jour les stocks et prix en temps reel.
    """
    serializer_class = AsPharmSyncPayloadSerializer
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        identifiant_as_pharm = serializer.validated_data["identifiant_as_pharm"]
        produits = serializer.validated_data["produits"]

        # 1. Recuperation de la pharmacie
        pharmacie = Pharmacie.objects.filter(identifiant_as_pharm=identifiant_as_pharm).first()
        if not pharmacie:
            return Response(
                {"erreur": f"Aucune pharmacie enregistree avec l'identifiant AS-Pharm '{identifiant_as_pharm}'."},
                status=status.HTTP_404_NOT_FOUND,
            )

        produits_traites = 0
        erreurs = []

        for item in produits:
            try:
                # 2. Creation ou mise a jour du Medicament
                medicament, _ = Medicament.objects.get_or_create(
                    nom__iexact=item["nom"].strip(),
                    defaults={
                        "nom": item["nom"].strip(),
                        "code_dci": item.get("code_dci", "").strip(),
                        "forme_dosage": item.get("forme_dosage", "").strip(),
                        "description": item.get("description", "").strip(),
                        "est_essentiel": item.get("est_essentiel", False),
                    },
                )

                # Si le medicament existait deja, on complete les infos si necessaire
                if not medicament.code_dci and item.get("code_dci"):
                    medicament.code_dci = item["code_dci"]
                    medicament.save()

                # 3. Creation ou mise a jour du Stock pour cette pharmacie
                quantite = item["quantite"]
                est_disponible = item.get("est_disponible", quantite > 0)

                StockPharmacie.objects.update_or_create(
                    pharmacie=pharmacie,
                    medicament=medicament,
                    defaults={
                        "quantite": quantite,
                        "prix": item["prix"],
                        "est_disponible": est_disponible,
                        "derniere_synchronisation": timezone.now(),
                    },
                )
                produits_traites += 1
            except Exception as e:
                erreurs.append(f"Erreur sur {item.get('nom')}: {str(e)}")

        # 4. Tracabilite dans AsPharmSyncLog
        statut_log = "succes" if len(erreurs) == 0 else "erreur"
        message_log = f"{produits_traites} produits synchronises."
        if erreurs:
            message_log += f" Erreurs : {'; '.join(erreurs[:5])}"

        AsPharmSyncLog.objects.create(
            pharmacie=pharmacie,
            type_synchronisation="stocks",
            statut=statut_log,
            nb_elements_traites=produits_traites,
            message=message_log,
            details={"total_recu": len(produits), "erreurs": erreurs},
        )

        return Response(
            {
                "statut": "succes",
                "pharmacie": pharmacie.nom,
                "identifiant_as_pharm": identifiant_as_pharm,
                "produits_synchronises": produits_traites,
                "date_synchronisation": timezone.now().isoformat(),
            },
            status=status.HTTP_200_OK,
        )


class AsPharmCommandesEnAttenteAPIView(generics.ListAPIView):
    """
    Permet au logiciel AS-Pharm d'extraire les commandes en attente pour son officine.
    """
    serializer_class = AsPharmCommandeSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        identifiant = self.kwargs.get("identifiant_as_pharm")
        return (
            Commande.objects.filter(
                pharmacie__identifiant_as_pharm=identifiant,
                statut="en_attente",
            )
            .select_related("utilisateur", "pharmacie")
            .prefetch_related("lignecommande_set__medicament")
            .order_by("date_commande")
        )


class AsPharmUpdateCommandeStatutAPIView(generics.GenericAPIView):
    """
    Permet au logiciel AS-Pharm de notifier DjimPharma du changement de statut (en preparation, prete, livree, etc.).
    """
    serializer_class = AsPharmUpdateCommandeStatutSerializer
    permission_classes = [AllowAny]

    def post(self, request, reference):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        commande = Commande.objects.filter(reference=reference).select_related("utilisateur", "pharmacie").first()
        if not commande:
            return Response({"erreur": "Commande introuvable."}, status=status.HTTP_404_NOT_FOUND)

        nouveau_statut = serializer.validated_data["statut"]
        motif = serializer.validated_data.get("motif", "")

        commande.statut = nouveau_statut
        commande.save()

        # Notification automatique au client
        messages = {
            "en_preparation": "Votre commande est en cours de préparation par la pharmacie.",
            "prete": f"Votre commande est prête ! Vous pouvez la retirer à la {commande.pharmacie.nom}.",
            "livree": "Votre commande a été livrée avec succès.",
            "annulee": f"Votre commande a été annulée. Motif : {motif or 'Indisponible'}",
        }

        Notification.objects.create(
            utilisateur=commande.utilisateur,
            titre=f"Commande {commande.get_statut_display()}",
            message=messages.get(nouveau_statut, f"Statut mis à jour : {nouveau_statut}"),
            type_notification="commande",
        )

        return Response(
            {
                "statut": "succes",
                "reference": str(commande.reference),
                "nouveau_statut": commande.statut,
            },
            status=status.HTTP_200_OK,
        )


class SyncPharmaciesGardeAPIView(generics.GenericAPIView):
    """
    Endpoint pour declencher la synchronisation des pharmacies de garde du Togo.
    Appelle l'API externe (Kondjigbale) ou le referentiel de l'Ordre National des Pharmaciens (ONPT).
    """
    permission_classes = [AllowAny]

    def post(self, request):
        from .services.togo_garde_sync import TogoPharmacieGardeService
        rapport = TogoPharmacieGardeService.synchroniser_gardes()
        return Response(rapport, status=status.HTTP_200_OK)
