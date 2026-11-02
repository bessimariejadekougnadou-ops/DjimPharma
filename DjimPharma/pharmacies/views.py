from datetime import timedelta
import re
import unicodedata
from django.db.models import Q
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.authentication import TokenAuthentication
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import HistoriqueGarde, PeriodeGarde, Pharmacie
from .serializers import (
    HistoriqueGardeSerializer,
    PeriodeGardeSerializer,
    PharmacieSerializer,
    PublicationGardeSerializer,
)
from .services.garde_service import GardeService
from .services.google_places_service import GooglePlacesService

STOPWORDS = {
    "de", "du", "des", "la", "le", "les", "a", "au", "aux", "en", "pour",
    "mon", "ma", "mes", "chez", "moi", "d", "l", "un", "une"
}
GENERIC_WORDS = {
    "pharmacie", "pharmacies", "officine", "officines", "pharma", "dispensaire"
}
GARDE_WORDS = {
    "garde", "gardes", "nuit", "24h", "urgence", "urgences"
}
PROCHE_WORDS = {
    "proche", "proches", "pres", "autour", "ici", "voisin", "voisine"
}


def _norm(text: str) -> str:
    if not text:
        return ""
    s = "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn").lower()
    s = re.sub(r"[^a-z0-9]", " ", s)
    s = s.replace("hedz", "hed").replace("nyeko", "nyiko")
    return " ".join(s.split())


class EstAdminOuPharmacien(permissions.BasePermission):
    """Permission permettant uniquement aux administrateurs ou pharmaciens de modifier les gardes."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        if request.user.is_superuser or request.user.is_staff:
            return True
        if hasattr(request.user, "profil") and request.user.profil.role in ["admin", "pharmacien"]:
            return True
        return False


class ListePharmaciesAPIView(generics.ListAPIView):
    """
    Retourne la liste des pharmacies avec filtres dynamiques (garde, ville, quartier, recherche).
    Tri intelligent par pertinence et par proximité géographique.
    """

    serializer_class = PharmacieSerializer

    def get_queryset(self):
        qs = Pharmacie.objects.filter(est_active=True)

        ville = self.request.query_params.get("ville")
        if ville and ville.strip() and ville.strip() != "Toutes":
            qs = qs.filter(ville__icontains=ville.strip())

        quartier = self.request.query_params.get("quartier") or self.request.query_params.get("zone")
        if quartier:
            qs = qs.filter(Q(quartier__icontains=quartier.strip()) | Q(adresse__icontains=quartier.strip()))

        de_garde = self.request.query_params.get("est_de_garde") or self.request.query_params.get("de_garde")
        if de_garde is not None:
            est_vrai = de_garde.lower() in ["true", "1", "oui"]
            qs = qs.filter(est_de_garde=est_vrai)

        recherche = self.request.query_params.get("recherche") or self.request.query_params.get("q")
        meaningful_tokens = []

        if recherche and recherche.strip():
            q_norm = _norm(recherche.strip())
            raw_tokens = q_norm.split()
            is_garde_intent = any(w in GARDE_WORDS for w in raw_tokens)

            if is_garde_intent:
                qs_garde = qs.filter(est_de_garde=True)
                if qs_garde.count() > 0:
                    qs = qs_garde

            meaningful_tokens = [
                w for w in raw_tokens
                if w not in STOPWORDS
                and w not in GENERIC_WORDS
                and w not in GARDE_WORDS
                and w not in PROCHE_WORDS
            ]

            if meaningful_tokens:
                matched_ids = []
                for p in qs:
                    haystack = _norm(f"{p.nom} {p.adresse} {p.quartier} {p.ville}")
                    haystack_collapsed = haystack.replace(" ", "")
                    q_collapsed = "".join(meaningful_tokens)
                    if any(token in haystack for token in meaningful_tokens) or (
                        len(q_collapsed) >= 3 and q_collapsed in haystack_collapsed
                    ):
                        matched_ids.append(p.id)
                qs = qs.filter(id__in=matched_ids)

        statut_verif = self.request.query_params.get("statut_verification")
        if statut_verif:
            qs = qs.filter(statut_verification=statut_verif)

        lat_str = self.request.query_params.get("lat")
        lng_str = self.request.query_params.get("lng")
        user_lat = float(lat_str) if lat_str else None
        user_lng = float(lng_str) if lng_str else None

        items = list(qs)

        if meaningful_tokens:
            def calc_score(p):
                nom_norm = _norm(p.nom)
                nom_words = [w for w in nom_norm.split() if w not in GENERIC_WORDS and w not in STOPWORDS]
                quartier_words = _norm(p.quartier).split()
                addr_words = _norm(f"{p.adresse} {p.ville}").split()

                if any(any(w.startswith(t) for w in nom_words) for t in meaningful_tokens):
                    score = 1
                elif any(t in nom_norm for t in meaningful_tokens):
                    score = 2
                elif any(any(w.startswith(t) for w in quartier_words) for t in meaningful_tokens):
                    score = 3
                elif any(any(w.startswith(t) for w in addr_words) for t in meaningful_tokens):
                    score = 4
                else:
                    score = 5

                dist = 999999.0
                if user_lat is not None and user_lng is not None and p.latitude is not None and p.longitude is not None:
                    dist = (p.latitude - user_lat) ** 2 + (p.longitude - user_lng) ** 2
                return (score, dist)

            items.sort(key=calc_score)
            return items
        elif user_lat is not None and user_lng is not None:
            items.sort(
                key=lambda p: (
                    (p.latitude - user_lat) ** 2 + (p.longitude - user_lng) ** 2
                    if p.latitude is not None and p.longitude is not None
                    else 999999.0
                )
            )
            return items

        return qs


class RechercheDynamiquePharmaciesAPIView(APIView):
    """
    Recherche dynamique de pharmacies connectée à Google Places API avec mise en cache,
    reconnaissance des établissements existants et statut de vérification ONPT.
    """

    def get(self, request):
        query = request.query_params.get("recherche") or request.query_params.get("q")
        ville = request.query_params.get("ville")
        lat_str = request.query_params.get("lat")
        lng_str = request.query_params.get("lng")
        radius_str = request.query_params.get("rayon")
        force_refresh = request.query_params.get("refresh", "").lower() in ["true", "1"]

        lat = float(lat_str) if lat_str else None
        lng = float(lng_str) if lng_str else None
        radius = int(radius_str) if radius_str else None

        service = GooglePlacesService()
        resultat = service.search_pharmacies(
            query=query,
            ville=ville,
            latitude=lat,
            longitude=lng,
            radius_meters=radius,
            force_refresh=force_refresh,
        )

        return Response(resultat, status=status.HTTP_200_OK)


class ListeGardesAPIView(generics.ListAPIView):
    """
    Liste les périodes de garde validées actuelles et futures.
    """

    serializer_class = PeriodeGardeSerializer

    def get_queryset(self):
        maintenant = timezone.now()
        qs = PeriodeGarde.objects.filter(statut_validation="valide", date_fin__gte=maintenant)

        ville = self.request.query_params.get("ville")
        if ville:
            qs = qs.filter(pharmacie__ville__icontains=ville.strip())

        zone = self.request.query_params.get("zone")
        if zone:
            qs = qs.filter(zone__icontains=zone.strip())

        actives_uniquement = self.request.query_params.get("actives", "").lower() in ["true", "1"]
        if actives_uniquement:
            qs = qs.filter(date_debut__lte=maintenant)

        return qs


class PublierGardeAPIView(APIView):
    """
    Publie ou valide une nouvelle période de garde (Accès réservé aux administrateurs et pharmaciens).
    """

    authentication_classes = [TokenAuthentication]
    permission_classes = [EstAdminOuPharmacien]

    def post(self, request):
        serializer = PublicationGardeSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        data = serializer.validated_data
        pharmacie = data["pharmacie"]
        date_debut = data["date_debut"]
        date_fin = data["date_fin"]
        zone = data.get("zone", "")
        source = data.get("source", "Tableau officiel ONPT Togo")
        commentaire = data.get("commentaire", "")

        try:
            periode = GardeService.publier_periode_garde(
                pharmacie=pharmacie,
                date_debut=date_debut,
                date_fin=date_fin,
                zone=zone,
                source=source,
                user=request.user,
                commentaire=commentaire,
                statut_validation="valide",
            )
            return Response(
                PeriodeGardeSerializer(periode).data,
                status=status.HTTP_201_CREATED,
            )
        except Exception as e:
            return Response({"erreur": str(e)}, status=status.HTTP_400_BAD_REQUEST)


class ImporterGardesAPIView(APIView):
    """
    Importation de masse d'un tableau officiel de gardes (ex: liste hebdomadaire ONPT).
    """

    authentication_classes = [TokenAuthentication]
    permission_classes = [EstAdminOuPharmacien]

    def post(self, request):
        gardes = request.data.get("gardes")
        if not isinstance(gardes, list) or not gardes:
            return Response(
                {"erreur": "Le champ 'gardes' doit être une liste non vide d'objets de garde."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        source_globale = request.data.get("source", "Tableau officiel ONPT Togo")
        resultat = GardeService.importer_tableau_gardes(
            lignes_donnees=gardes,
            user=request.user,
            source_globale=source_globale,
        )

        return Response(resultat, status=status.HTTP_200_OK)


class ActualiserGardesAPIView(APIView):
    """
    Déclenche le recalcul immédiat des gardes (activation / expiration).
    Accessible publiquement ou via tâche planifiée pour rafraîchir la carte.
    """

    def post(self, request):
        user = request.user if request.user.is_authenticated else None
        rapport = GardeService.verifier_et_actualiser_toutes_les_gardes(modifie_par=user)
        return Response(rapport, status=status.HTTP_200_OK)


class StatistiquesGardesAPIView(APIView):
    """
    Fournit les statistiques de surveillance :
    - Nombre de gardes actives par ville
    - Alertes sur les gardes expirant dans moins de 24h
    - Détection des villes sans garde active
    """

    def get(self, request):
        maintenant = timezone.now()
        bientot = maintenant + timedelta(hours=24)

        gardes_actives = PeriodeGarde.objects.filter(
            statut_validation="valide",
            date_debut__lte=maintenant,
            date_fin__gte=maintenant,
        )

        expirations_proches = PeriodeGarde.objects.filter(
            statut_validation="valide",
            date_fin__gte=maintenant,
            date_fin__lte=bientot,
        )

        # Répartition par ville
        villes_connues = ["Lomé", "Kara", "Sokodé", "Kpalimé", "Atakpamé", "Dapaong", "Tsévié", "Aného"]
        repartition = {}
        villes_sans_garde = []

        for ville in villes_connues:
            nb = gardes_actives.filter(pharmacie__ville__icontains=ville).count()
            repartition[ville] = nb
            if nb == 0:
                villes_sans_garde.append(ville)

        return Response(
            {
                "timestamp": maintenant.isoformat(),
                "total_gardes_actives": gardes_actives.count(),
                "total_expirations_prochaines_24h": expirations_proches.count(),
                "repartition_par_ville": repartition,
                "villes_sans_garde_active": villes_sans_garde,
                "alertes": [
                    f"Attention : La garde de {g.pharmacie.nom} ({g.pharmacie.ville}) expire le {g.date_fin:%d/%m à %H:%M}."
                    for g in expirations_proches[:5]
                ],
                "message": (
                    "Toutes les zones couvertes."
                    if not villes_sans_garde
                    else f"Attention : Aucune garde confirmée dans : {', '.join(villes_sans_garde)}."
                ),
            },
            status=status.HTTP_200_OK,
        )


class HistoriqueGardesAPIView(generics.ListAPIView):
    """
    Journal d'audit des modifications de garde (qui a changé quoi et quand).
    """

    serializer_class = HistoriqueGardeSerializer
    authentication_classes = [TokenAuthentication]
    permission_classes = [EstAdminOuPharmacien]
    queryset = HistoriqueGarde.objects.all()[:100]
