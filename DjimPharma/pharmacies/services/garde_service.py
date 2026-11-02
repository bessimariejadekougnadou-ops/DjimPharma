"""
Service de gestion dynamique et automatisée des pharmacies de garde pour DjimPharma.
Gère :
- Le calcul en temps réel du statut de garde (activation et expiration selon l'heure locale Africa/Lome).
- L'audit et la traçabilité des modifications (qui a validé quoi et quand).
- L'envoi ciblé des notifications de garde selon les préférences des utilisateurs.
- L'importation de tableaux officiels de garde (ONPT Togo).
"""

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional
from django.contrib.auth.models import User
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from notifications.models import Notification, PreferenceNotificationGarde
from pharmacies.models import HistoriqueGarde, PeriodeGarde, Pharmacie
from utilisateurs.models import Utilisateur

logger = logging.getLogger(__name__)


class GardeService:
    @classmethod
    def verifier_et_actualiser_toutes_les_gardes(cls, modifie_par: Optional[User] = None) -> Dict[str, Any]:
        """
        Vérifie et met à jour immédiatement les statuts de garde de toutes les pharmacies.
        - Active les gardes dont la période a débuté.
        - Clôture (expire) les gardes terminées.
        - Enregistre l'historique d'audit.
        """
        maintenant = timezone.now()
        gardes_expirees_count = 0
        statuts_modifies_count = 0
        pharmacies_de_garde = []

        with transaction.atomic():
            # 1. Marquer comme expirées les périodes validées dont date_fin est dépassée
            periodes_a_expirer = PeriodeGarde.objects.filter(
                statut_validation="valide",
                date_fin__lt=maintenant,
            )
            for pg in periodes_a_expirer:
                pg.statut_validation = "expire"
                pg.save(update_fields=["statut_validation", "date_modification"])
                gardes_expirees_count += 1
                HistoriqueGarde.objects.create(
                    periode_garde=pg,
                    pharmacie=pg.pharmacie,
                    action="EXPIRATION",
                    modifie_par=modifie_par,
                    details={"motif": "Clôture automatique : date de fin dépassée"},
                )

            # 2. Recalculer le statut est_de_garde de chaque pharmacie
            for pharmacie in Pharmacie.objects.filter(est_active=True):
                ancien_statut = pharmacie.est_de_garde
                active_periode = pharmacie.periode_garde_active()
                nouveau_statut = active_periode is not None

                if ancien_statut != nouveau_statut:
                    pharmacie.est_de_garde = nouveau_statut
                    pharmacie.save(update_fields=["est_de_garde"])
                    statuts_modifies_count += 1

                    HistoriqueGarde.objects.create(
                        pharmacie=pharmacie,
                        periode_garde=active_periode,
                        action="SYNCHRO_AUTOMATIQUE",
                        modifie_par=modifie_par,
                        details={
                            "ancien_statut": ancien_statut,
                            "nouveau_statut": nouveau_statut,
                            "periode_id": active_periode.id if active_periode else None,
                        },
                    )

                if nouveau_statut:
                    pharmacies_de_garde.append({
                        "id": pharmacie.id,
                        "nom": pharmacie.nom,
                        "ville": pharmacie.ville,
                        "date_fin": active_periode.date_fin.isoformat() if active_periode else None,
                    })

        logger.info(
            f"Actualisation des gardes terminée : {statuts_modifies_count} statuts modifiés, "
            f"{gardes_expirees_count} gardes expirées, {len(pharmacies_de_garde)} pharmacies actives."
        )

        return {
            "timestamp": maintenant.isoformat(),
            "statuts_modifies": statuts_modifies_count,
            "gardes_expirees": gardes_expirees_count,
            "total_gardes_actives": len(pharmacies_de_garde),
            "pharmacies_de_garde": pharmacies_de_garde,
        }

    @classmethod
    def publier_periode_garde(
        cls,
        pharmacie: Pharmacie,
        date_debut: datetime,
        date_fin: datetime,
        zone: str = "",
        source: str = "Tableau officiel ONPT Togo",
        user: Optional[User] = None,
        commentaire: str = "",
        statut_validation: str = "valide",
    ) -> PeriodeGarde:
        """
        Publie et valide une période de garde après contrôles d'intégrité et sécurité.
        Déclenche immédiatement la mise à jour et la notification aux utilisateurs ciblés.
        """
        if date_fin <= date_debut:
            raise ValidationError("La date de fin de garde doit être strictement postérieure à la date de début.")

        maintenant = timezone.now()

        with transaction.atomic():
            periode = PeriodeGarde.objects.create(
                pharmacie=pharmacie,
                date_debut=date_debut,
                date_fin=date_fin,
                zone=zone or f"{pharmacie.ville} - Centre",
                source=source,
                date_verification=maintenant,
                statut_validation=statut_validation,
                valide_par=user,
                commentaire=commentaire,
            )

            # Historique de traçabilité
            HistoriqueGarde.objects.create(
                periode_garde=periode,
                pharmacie=pharmacie,
                action="VALIDATION" if statut_validation == "valide" else "CREATION",
                modifie_par=user,
                details={
                    "date_debut": date_debut.isoformat(),
                    "date_fin": date_fin.isoformat(),
                    "zone": periode.zone,
                    "source": source,
                },
            )

            # Mise à jour immédiate du statut de la pharmacie
            pharmacie.actualiser_statut_garde()

            # Déclenchement des notifications si la période est validée
            if statut_validation == "valide":
                cls.notifier_utilisateurs_garde(periode)

        return periode

    @classmethod
    def notifier_utilisateurs_garde(cls, periode: PeriodeGarde) -> int:
        """
        Envoie des notifications ciblées aux utilisateurs concernés par cette garde.
        Évite le spam national en filtrant par ville et zone selon leurs préférences.
        """
        pharmacie = periode.pharmacie
        ville_cible = pharmacie.ville
        zone_cible = periode.zone

        # Formatage des dates au format local Togo (Africa/Lome)
        tz_lome = timezone.get_current_timezone()
        debut_local = periode.date_debut.astimezone(tz_lome).strftime("%d/%m/%Y à %H:%M")
        fin_local = periode.date_fin.astimezone(tz_lome).strftime("%d/%m/%Y à %H:%M")
        verif_local = periode.date_verification.astimezone(tz_lome).strftime("%d/%m/%Y à %H:%M")

        titre = f"🛡️ Pharmacie de garde : {pharmacie.nom}"
        lignes = [
            f"La pharmacie {pharmacie.nom} ({pharmacie.adresse}) est de garde.",
            f"• Période : du {debut_local} au {fin_local}",
            f"• Zone : {zone_cible or ville_cible}",
            f"• Source officielle : {periode.source}",
            f"• Vérifié le {verif_local} (Heure du Togo).",
        ]
        message = "\n".join(lignes)

        donnees = {
            "type": "garde",
            "pharmacie_id": pharmacie.id,
            "pharmacie_nom": pharmacie.nom,
            "latitude": pharmacie.latitude,
            "longitude": pharmacie.longitude,
            "telephone": pharmacie.telephone,
            "date_debut": periode.date_debut.isoformat(),
            "date_fin": periode.date_fin.isoformat(),
            "source": periode.source,
        }

        # Utilisateurs ayant configuré cette ville ou zone et accepté les alertes
        preferences = PreferenceNotificationGarde.objects.filter(
            recevoir_alertes_garde=True,
            ville__icontains=ville_cible,
        )

        nb_envoyes = 0
        destinataires_ids = set()

        for pref in preferences:
            destinataires_ids.add(pref.utilisateur_id)

        # Si aucun utilisateur n'a défini de préférence spécifique, notifier les clients de cette ville
        if not destinataires_ids:
            clients_ville = Utilisateur.objects.filter(
                est_actif=True,
                ville__icontains=ville_cible,
            )[:50]
            for c in clients_ville:
                destinataires_ids.add(c.id)

        # Création des notifications in-app
        notifications_a_creer = [
            Notification(
                utilisateur_id=uid,
                titre=titre,
                message=message,
                type_notification="garde",
                canal="application",
                donnees_supplementaires=donnees,
            )
            for uid in destinataires_ids
        ]

        if notifications_a_creer:
            Notification.objects.bulk_create(notifications_a_creer)
            nb_envoyes = len(notifications_a_creer)

        logger.info(f"Notification garde envoyée à {nb_envoyes} utilisateurs pour {pharmacie.nom}.")
        return nb_envoyes

    @classmethod
    def importer_tableau_gardes(
        cls,
        lignes_donnees: List[Dict[str, Any]],
        user: Optional[User] = None,
        source_globale: str = "Tableau officiel ONPT Togo",
    ) -> Dict[str, Any]:
        """
        Importe un tableau de gardes structuré (ex: liste hebdomadaire ONPT Togo).
        """
        gardes_creees = 0
        erreurs = []

        for index, item in enumerate(lignes_donnees, start=1):
            try:
                nom_pharma = item.get("nom", "").strip()
                ville = item.get("ville", "Lomé").strip()
                date_debut_str = item.get("date_debut")
                date_fin_str = item.get("date_fin")
                zone = item.get("zone", "").strip()
                source = item.get("source", source_globale)

                if not nom_pharma or not date_debut_str or not date_fin_str:
                    erreurs.append(f"Ligne {index}: Nom, date_debut ou date_fin manquant.")
                    continue

                date_debut = datetime.fromisoformat(date_debut_str)
                date_fin = datetime.fromisoformat(date_fin_str)
                if timezone.is_naive(date_debut):
                    date_debut = timezone.make_aware(date_debut)
                if timezone.is_naive(date_fin):
                    date_fin = timezone.make_aware(date_fin)

                # Recherche ou création de la pharmacie
                pharmacie = Pharmacie.objects.filter(
                    nom__icontains=nom_pharma,
                    ville__icontains=ville,
                ).first()

                if not pharmacie:
                    pharmacie = Pharmacie.objects.filter(nom__icontains=nom_pharma).first()

                if not pharmacie:
                    identifiant = f"onpt_{nom_pharma.lower().replace(' ', '_')[:30]}_{int(timezone.now().timestamp())}"
                    pharmacie = Pharmacie.objects.create(
                        nom=nom_pharma,
                        adresse=item.get("adresse", f"Adresse déclarée ONPT ({ville})"),
                        ville=ville,
                        telephone=item.get("telephone", ""),
                        est_de_garde=False,
                        identifiant_as_pharm=identifiant,
                        latitude=item.get("latitude"),
                        longitude=item.get("longitude"),
                        source_donnees="onpt_officiel",
                        statut_verification="verifiee_officielle",
                        source_verification="Ordre National des Pharmaciens du Togo (ONPT)",
                        date_derniere_synchro=timezone.now(),
                    )

                cls.publier_periode_garde(
                    pharmacie=pharmacie,
                    date_debut=date_debut,
                    date_fin=date_fin,
                    zone=zone,
                    source=source,
                    user=user,
                    commentaire=item.get("commentaire", "Importation automatique tableau officiel ONPT"),
                )
                gardes_creees += 1

            except Exception as e:
                erreurs.append(f"Ligne {index} ({item.get('nom')}): {str(e)}")

        # Actualisation générale
        cls.verifier_et_actualiser_toutes_les_gardes(modifie_par=user)

        return {
            "total_traite": len(lignes_donnees),
            "gardes_creees": gardes_creees,
            "erreurs": erreurs,
        }
