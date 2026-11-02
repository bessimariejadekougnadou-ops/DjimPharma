import re
import unicodedata
from decimal import Decimal
from django.utils import timezone
from django.core.paginator import Paginator
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny

from pharmacies.models import Pharmacie
from medicaments.models import Medicament, normaliser_chaine
from stocks.models import StockPharmacie


def normaliser_recherche_pharmacie(texte: str) -> str:
    """Normalisation tolérante selon la norme Pharivia :
    majuscules, accents, espaces en trop et espaces entre dosage et unité ignorés.
    Exemple: 'DOLIPRANE  1000 MG' -> 'doliprane 1000mg'
    """
    if not texte:
        return ""
    texte_sans_accents = "".join(
        c for c in unicodedata.normalize("NFD", texte)
        if unicodedata.category(c) != "Mn"
    )
    # Suppression espaces multiples
    texte_clean = " ".join(texte_sans_accents.lower().split())
    # Fusion espace entre chiffre et unité (ex: '1000 mg' -> '1000mg', '500 ml' -> '500ml')
    texte_clean = re.sub(r'(\d+)\s+(mg|g|ml|l|ui|mcg|µg|cp|gel)\b', r'\1\2', texte_clean)
    return texte_clean


def get_pharmacie_from_bearer(request):
    """Extrait et valide le Bearer token de la pharmacie (pca_live_... ou identifiant)."""
    auth_header = request.headers.get("Authorization", "")
    token = ""
    if auth_header.startswith("Bearer "):
        token = auth_header[7:].strip()
    elif request.headers.get("X-API-KEY"):
        token = request.headers.get("X-API-KEY", "").strip()

    if not token:
        return None, Response(
            {"erreur": "En-tête 'Authorization: Bearer pca_live_...' requis pour cette opération."},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    pharmacie = Pharmacie.objects.filter(cle_api=token).first()
    if not pharmacie:
        # Repli de rétrocompatibilité sur identifiant_as_pharm
        pharmacie = Pharmacie.objects.filter(identifiant_as_pharm=token).first()

    if not pharmacie:
        return None, Response(
            {"erreur": "Clé API invalide, révoquée ou inconnue de la plateforme DjimPharma."},
            status=status.HTTP_401_UNAUTHORIZED,
        )

    if not pharmacie.est_active:
        return None, Response(
            {"erreur": "Le compte de cette pharmacie n'est pas encore validé par l'administration ou est désactivé."},
            status=status.HTTP_403_FORBIDDEN,
        )

    return pharmacie, None


class PhariviaVersionAPIView(APIView):
    """
    GET /api/v1/version
    Endpoint public officiel Pharivia.
    Permet à n'importe quel logiciel d'officine (caisse, ERP) de vérifier la compatibilité.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({
            "versionActuelle": "1.2.0",
            "versionMinimale": "1.0.0",
            "statut": "stable",
            "plateforme": "DjimPharma",
            "pays": ["TOGO"],
            "devise": {
                "code": "XOF",
                "symbole": "FCFA",
                "nom": "Franc CFA UEMOA",
            },
            "notesDeVersion": [
                {
                    "version": "1.2.0",
                    "date": "2026-10-16",
                    "changements": [
                        "Intégration du protocole standard Pharivia pour le Togo (Lomé).",
                        "Rattachement automatique au catalogue officiel LNME Togo.",
                        "Calcul automatique de disponibilité (DISPONIBLE, STOCK_FAIBLE, RUPTURE).",
                        "Support des devises XOF (Francs CFA) sans conversion requise."
                    ],
                },
                {
                    "version": "1.1.0",
                    "date": "2026-09-07",
                    "changements": ["Ajout du champ devise XOF / FCFA."],
                },
                {
                    "version": "1.0.0",
                    "date": "2026-08-09",
                    "changements": ["Première version publique : synchronisation du stock, profil pharmacie."],
                }
            ],
            "documentation": "https://www.pharivia.com/documentation-api",
        }, status=status.HTTP_200_OK)


class PhariviaPharmacieAPIView(APIView):
    """
    GET /api/v1/pharmacie
    Confirme l'identité de l'officine liée à la clé API Bearer.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        pharmacie, error_resp = get_pharmacie_from_bearer(request)
        if error_resp:
            return error_resp

        return Response({
            "id": f"pharma_{pharmacie.id}",
            "nom": pharmacie.nom,
            "pays": "TOGO",
            "ville": pharmacie.ville,
            "quartier": pharmacie.quartier or "",
            "devise": {
                "code": "XOF",
                "symbole": "FCFA",
            },
            "adresse": pharmacie.adresse,
            "telephone": pharmacie.telephone,
            "estDeGarde": pharmacie.est_de_garde,
            "statutValidation": "VALIDEE" if pharmacie.est_active else "EN_ATTENTE",
            "latitude": pharmacie.latitude,
            "longitude": pharmacie.longitude,
        }, status=status.HTTP_200_OK)


class PhariviaStockAPIView(APIView):
    """
    GET /api/v1/stock  -> Lecture de l'inventaire actuel de l'officine
    PUT /api/v1/stock  -> Synchronisation en masse (jusqu'à 500 lignes par appel)
    POST /api/v1/stock -> Alias pour les logiciels n'envoyant que du POST
    """
    permission_classes = [AllowAny]

    def get(self, request):
        pharmacie, error_resp = get_pharmacie_from_bearer(request)
        if error_resp:
            return error_resp

        page = int(request.query_params.get("page", 1))
        limite = min(int(request.query_params.get("limite", 1000)), 1000)

        stocks_qs = StockPharmacie.objects.filter(pharmacie=pharmacie).select_related("medicament").order_by("medicament__nom")
        paginator = Paginator(stocks_qs, limite)

        current_page = paginator.get_page(page)
        lignes = []

        for s in current_page:
            q = s.quantite
            if q == 0:
                statut_str = "RUPTURE"
            elif q <= 10:
                statut_str = "STOCK_FAIBLE"
            else:
                statut_str = "DISPONIBLE"

            lignes.append({
                "codeExterne": s.code_externe or f"DJIM-{s.medicament.id}",
                "medicament": {
                    "nom": s.medicament.nom,
                    "molecule": s.medicament.dci or s.medicament.nom,
                    "categorie": s.medicament.categorie_therapeutique or s.medicament.forme_pharmaceutique or "Médicament",
                },
                "quantite": q,
                "prix": int(s.prix) if s.prix == int(s.prix) else float(s.prix),
                "statut": statut_str,
                "derniereMaj": s.derniere_synchronisation.isoformat(),
            })

        return Response({
            "pagination": {
                "page": page,
                "limite": limite,
                "total": paginator.count,
                "totalPages": paginator.num_pages,
                "aPlusDePages": current_page.has_next(),
            },
            "devise": "XOF",
            "stock": lignes,
        }, status=status.HTTP_200_OK)

    def put(self, request):
        return self._synchroniser(request)

    def post(self, request):
        return self._synchroniser(request)

    def _synchroniser(self, request):
        pharmacie, error_resp = get_pharmacie_from_bearer(request)
        if error_resp:
            return error_resp

        data = request.data
        if not isinstance(data, dict) or "lignes" not in data:
            return Response(
                {"erreur": "Le corps de la requête doit être un objet JSON contenant le tableau 'lignes'."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        lignes = data.get("lignes", [])
        if not isinstance(lignes, list):
            return Response(
                {"erreur": "Le champ 'lignes' doit être une liste de produits."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if len(lignes) > 500:
            return Response(
                {"erreur": "La taille maximale par lot est de 500 lignes. Veuillez découper en plusieurs appels."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        resultats = []
        synchronisees = 0
        erreurs = 0

        for ligne in lignes:
            try:
                code_ext = str(ligne.get("codeExterne", "") or "").strip()
                nom_brut = str(ligne.get("nom", "") or "").strip()
                molecule = str(ligne.get("molecule", "") or "").strip()
                categorie = str(ligne.get("categorie", "") or "").strip()

                if not nom_brut and not code_ext:
                    resultats.append({
                        "statut": "erreur",
                        "message": "Le champ 'nom' ou 'codeExterne' est obligatoire.",
                    })
                    erreurs += 1
                    continue

                # Quantité et prix
                raw_qte = ligne.get("quantite", 0)
                raw_prix = ligne.get("prix", 0)

                try:
                    quantite = max(0, int(raw_qte))
                except (ValueError, TypeError):
                    quantite = 0

                try:
                    prix = Decimal(str(raw_prix))
                    if prix < 0:
                        prix = Decimal("0")
                except Exception:
                    prix = Decimal("0")

                # Résolution du médicament selon la priorité Pharivia :
                # 1. Par codeExterne s'il a déjà été enregistré pour cette pharmacie
                stock_existant = None
                if code_ext:
                    stock_existant = StockPharmacie.objects.filter(
                        pharmacie=pharmacie,
                        code_externe=code_ext,
                    ).select_related("medicament").first()

                medicament = None
                if stock_existant:
                    medicament = stock_existant.medicament
                else:
                    # 2. Recherche tolérante par nom dans le catalogue
                    nom_norm = normaliser_recherche_pharmacie(nom_brut)
                    if nom_norm:
                        # Chercher dans le catalogue existant
                        tokens = nom_norm.split()
                        qs = Medicament.objects.filter(est_actif=True)
                        for token in tokens:
                            qs = qs.filter(nom_normalise__icontains=token)
                        medicament = qs.first()

                        # Si non trouvé, tentative par DCI
                        if not medicament and molecule:
                            mol_norm = normaliser_recherche_pharmacie(molecule)
                            medicament = Medicament.objects.filter(
                                nom_normalise__icontains=mol_norm,
                                est_actif=True,
                            ).first()

                    # 3. Si toujours aucun médicament existant, création dans le catalogue
                    if not medicament and nom_brut:
                        medicament = Medicament.objects.create(
                            nom=nom_brut,
                            dci=molecule or nom_brut,
                            categorie_therapeutique=categorie or "Médicament d'officine",
                            source_information="Synchronisation Pharivia Officine",
                            statut_reglementaire="non_precise",
                            est_actif=True,
                        )

                # Calcul du statut de disponibilité automatique (Règle Pharivia)
                # 0 -> RUPTURE, <= 10 -> STOCK_FAIBLE, > 10 -> DISPONIBLE
                if quantite == 0:
                    statut_pharivia = "RUPTURE"
                    est_disponible = False
                elif quantite <= 10:
                    statut_pharivia = "STOCK_FAIBLE"
                    est_disponible = True
                else:
                    statut_pharivia = "DISPONIBLE"
                    est_disponible = True

                # Mise à jour ou création du stock pour cette pharmacie
                stock, _ = StockPharmacie.objects.update_or_create(
                    pharmacie=pharmacie,
                    medicament=medicament,
                    defaults={
                        "quantite": quantite,
                        "prix": prix,
                        "est_disponible": est_disponible,
                        "code_externe": code_ext,
                        "derniere_synchronisation": timezone.now(),
                    },
                )

                resultats.append({
                    "codeExterne": code_ext or f"DJIM-{medicament.id}",
                    "nom": medicament.nom,
                    "statut": "ok",
                    "statutDisponibilite": statut_pharivia,
                    "quantite": quantite,
                    "prix": int(prix) if prix == int(prix) else float(prix),
                })
                synchronisees += 1

            except Exception as e:
                erreurs += 1
                resultats.append({
                    "nom": ligne.get("nom", "Inconnu"),
                    "statut": "erreur",
                    "details": str(e),
                })

        return Response({
            "synchronisees": synchronisees,
            "erreurs": erreurs,
            "pharmacie": pharmacie.nom,
            "devise": "XOF",
            "date": timezone.now().isoformat(),
            "resultats": resultats,
        }, status=status.HTTP_200_OK)
