from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.pagination import PageNumberPagination
from django.db.models import Q, Count
from .models import Medicament, DemandeDisponibilite, normaliser_chaine
from .serializers import MedicamentSerializer, DemandeDisponibiliteSerializer
from pharmacies.models import Pharmacie
from pharmacies.serializers import PharmacieSerializer


EQUIVALENCES_MEDICAMENTS = {
    # Paracétamol, Panadol, Doliprane et dérivés
    "pandol": ["panadol", "paracetamol"],
    "panado": ["panadol", "paracetamol"],
    "panadol": ["panadol", "paracetamol", "pandol"],
    "doli": ["doliprane", "paracetamol"],
    "dolipran": ["doliprane", "paracetamol"],
    "doliprane": ["doliprane", "paracetamol"],
    "efferalgan": ["efferalgan", "paracetamol"],
    "dafalgan": ["dafalgan", "paracetamol"],
    "paralyoc": ["paralyoc", "paracetamol"],
    "paracetam": ["paracetamol"],
    "paracetamol": ["paracetamol", "panadol", "doliprane", "efferalgan"],

    # Antibiotiques
    "amox": ["amoxicilline", "amoxil"],
    "amoxi": ["amoxicilline", "amoxil"],
    "amoxil": ["amoxil", "amoxicilline"],
    "amoxicilline": ["amoxicilline", "amoxil", "augmentin"],
    "augmentin": ["augmentin", "amoxicilline"],
    "flagyl": ["flagyl", "metronidazole"],
    "metronidazole": ["metronidazole", "flagyl"],
    "cipro": ["ciprofloxacine", "ciflox"],
    "ciflox": ["ciflox", "ciprofloxacine"],
    "ciprofloxacine": ["ciprofloxacine", "cipro", "ciflox"],
    "bactrim": ["bactrim", "cotrimoxazole"],
    "cotrimoxazole": ["cotrimoxazole", "bactrim"],

    # Paludisme (Antipaludiques courants au Togo)
    "coartem": ["coartem", "artemether", "lumefantrine"],
    "lonart": ["lonart", "artemether", "lumefantrine"],
    "artefan": ["artefan", "artemether", "lumefantrine"],
    "lumartem": ["lumartem", "artemether", "lumefantrine"],
    "artemether": ["artemether", "coartem", "lonart", "artefan"],

    # Anti-inflammatoires, Spasmes, Douleurs
    "ibu": ["ibuprofene", "advil"],
    "ibuprofene": ["ibuprofene", "advil"],
    "advil": ["advil", "ibuprofene"],
    "spasfon": ["spasfon", "phloroglucinol"],
    "phloroglucinol": ["phloroglucinol", "spasfon"],
    "cataflam": ["cataflam", "diclofenac"],
    "voltaren": ["voltaren", "voltarène", "diclofenac"],
    "voltarène": ["voltaren", "diclofenac"],
    "diclofenac": ["diclofenac", "cataflam", "voltaren"],
    "aspegic": ["aspegic", "aspirine"],
    "aspirine": ["aspirine", "aspegic"],

    # Allergies et Système respiratoire
    "ventoline": ["ventoline", "salbutamol"],
    "salbutamol": ["salbutamol", "ventoline"],
    "cetirizine": ["cetirizine", "zyrtec"],
    "zyrtec": ["zyrtec", "cetirizine"],
}


class CataloguePagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100


class ListeMedicamentsAPIView(generics.ListAPIView):
    """
    API de consultation et recherche du catalogue officiel des médicaments.
    Permet une recherche insensible aux accents et à la casse par nom, DCI,
    marques populaires (Panadol, Doliprane, Coartem...), forme ou catégorie.
    Les médicaments ayant du stock confirmé sont automatiquement placés en tête de liste.
    """
    serializer_class = MedicamentSerializer
    pagination_class = CataloguePagination

    def get_queryset(self):
        qs = Medicament.objects.filter(est_actif=True)

        query = self.request.query_params.get("q", "").strip()
        dci_param = self.request.query_params.get("dci", "").strip()
        forme_param = self.request.query_params.get("forme", "").strip()
        dosage_param = self.request.query_params.get("dosage", "").strip()
        cat_param = self.request.query_params.get("categorie", "").strip()
        essentiel_param = self.request.query_params.get("est_essentiel", "").strip()

        # Recherche intelligente tolérante aux équivalences de marques et fautes de frappe
        if query:
            tokens = normaliser_chaine(query).split()
            query_filter = Q()
            for token in tokens:
                token_clean = normaliser_chaine(token)
                term_q = Q(nom_normalise__icontains=token_clean) | Q(nom__icontains=token) | Q(dci__icontains=token)

                # Expansion via le dictionnaire de marques courantes
                synonymes = set()
                for k, syn_list in EQUIVALENCES_MEDICAMENTS.items():
                    if k == token_clean or (len(token_clean) >= 4 and (k.startswith(token_clean) or token_clean.startswith(k))):
                        synonymes.add(k)
                        synonymes.update(syn_list)

                for syn in synonymes:
                    syn_norm = normaliser_chaine(syn)
                    term_q |= Q(nom_normalise__icontains=syn_norm) | Q(nom__icontains=syn) | Q(dci__icontains=syn)

                query_filter &= term_q

            qs = qs.filter(query_filter)

        # Filtres spécifiques
        if dci_param:
            dci_norm = normaliser_chaine(dci_param)
            qs = qs.filter(nom_normalise__icontains=dci_norm)
        if forme_param:
            qs = qs.filter(forme_pharmaceutique__icontains=forme_param)
        if dosage_param:
            qs = qs.filter(dosage__icontains=dosage_param)
        if cat_param:
            qs = qs.filter(categorie_therapeutique__icontains=cat_param)
        if essentiel_param.lower() in ["true", "1", "oui"]:
            qs = qs.filter(est_essentiel=True)

        # Priorisation intelligente : en stock d'abord, puis ordre alphabétique
        qs = qs.annotate(
            a_du_stock=Count("stocks", filter=Q(stocks__est_disponible=True, stocks__quantite__gt=0))
        ).order_by("-a_du_stock", "nom")

        return qs


class DetailMedicamentAPIView(generics.RetrieveAPIView):
    """
    Fiche détaillée d'un médicament du catalogue.
    Retourne les informations du médicament ainsi que la liste des pharmacies de garde
    recommandées pour contact direct (puisqu'aucune donnée de stock AS-Pharma n'est encore connectée).
    """
    queryset = Medicament.objects.filter(est_actif=True)
    serializer_class = MedicamentSerializer

    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        serializer = self.get_serializer(instance)
        data = serializer.data

        # Ajouter des pharmacies de garde recommandées pour contact en 1 clic
        pharmacies_de_garde = Pharmacie.objects.filter(est_de_garde=True)[:5]
        data["pharmacies_contact_recommandees"] = PharmacieSerializer(pharmacies_de_garde, many=True).data

        return Response(data)


class CategoriesMedicamentsAPIView(generics.GenericAPIView):
    """
    Liste les catégories / classes thérapeutiques distinctes présentes dans le catalogue officiel.
    """
    def get(self, request, *args, **kwargs):
        categories = (
            Medicament.objects.filter(est_actif=True)
            .exclude(categorie_therapeutique="")
            .values_list("categorie_therapeutique", flat=True)
            .distinct()
            .order_by("categorie_therapeutique")
        )
        return Response({"categories": list(categories)})


class DemandeDisponibiliteCreateAPIView(generics.CreateAPIView):
    """
    Permet à un patient d'envoyer une demande de vérification de disponibilité
    d'un médicament à une pharmacie cible.
    """
    queryset = DemandeDisponibilite.objects.all()
    serializer_class = DemandeDisponibiliteSerializer
