import json
import os
from django.core.management.base import BaseCommand
from medicaments.models import Medicament, normaliser_chaine


class Command(BaseCommand):
    help = "Importe le catalogue officiel des médicaments du Togo extrait de l'Arrêté N° 147/2021/MSHPAUS"

    def add_arguments(self, parser):
        parser.add_argument(
            "--fichier",
            type=str,
            default="medicaments/data/catalogue_togo_officiel.json",
            help="Chemin vers le fichier JSON extrait",
        )
        parser.add_argument(
            "--inclure-a-valider",
            action="store_true",
            default=True,
            help="Importer également les entrées marquées comme nécessitant validation manuelle",
        )
        parser.add_argument(
            "--desactiver-demo",
            action="store_true",
            default=True,
            help="Désactiver les anciens médicaments de démonstration non issus de la liste officielle",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Mode simulation sans écriture en base de données",
        )

    def handle(self, *args, **options):
        fichier_path = options["fichier"]
        dry_run = options["dry_run"]
        inclure_a_valider = options["inclure_a_valider"]
        desactiver_demo = options["desactiver_demo"]

        if not os.path.exists(fichier_path):
            self.stderr.write(self.style.ERROR(f"Fichier introuvable : {fichier_path}"))
            return

        with open(fichier_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        stats_extract = data.get("statistiques", {})
        valides = data.get("medicaments_valides", [])
        a_valider = data.get("medicaments_a_valider", [])
        doublons = data.get("doublons_detectes", [])

        self.stdout.write(self.style.SUCCESS("=" * 65))
        self.stdout.write(self.style.SUCCESS("IMPORTATION DU CATALOGUE OFFICIEL DES MEDICAMENTS DU TOGO"))
        self.stdout.write(f"Source : {stats_extract.get('source', 'Arrêté N° 147/2021/MSHPAUS')}")
        self.stdout.write(f"Statut attribué : {stats_extract.get('statut_reglementaire')} ({stats_extract.get('mention_amm')})")
        self.stdout.write("=" * 65)

        if dry_run:
            self.stdout.write(self.style.WARNING("--- MODE DRY-RUN ACTIF (aucune écriture en base) ---"))

        # Gestion des 22 médicaments de test existants
        if desactiver_demo and not dry_run:
            # Marquer comme inactifs les anciens médicaments sans source officielle
            anciens = Medicament.objects.filter(source_information="").update(est_actif=False)
            self.stdout.write(f"Anciens médicaments de démo sans source officielle archivés : {anciens}")

        a_importer = list(valides)
        if inclure_a_valider:
            a_importer.extend(a_valider)

        nb_crees = 0
        nb_mis_a_jour = 0
        nb_erreurs = 0

        for item in a_importer:
            dci = item.get("dci", "").strip()
            forme = item.get("forme_pharmaceutique", "").strip()
            dosage = item.get("dosage", "").strip()
            nom = item.get("nom", "").strip() or dci
            cat = item.get("categorie_therapeutique", "").strip()
            niveaux = item.get("niveaux_soins", "").strip()
            necessite_validation = item.get("necessite_validation_manuelle", False)
            notes_val = item.get("notes_validation", "").strip()
            source = item.get("source_information", "Arrêté N° 147/2021/MSHPAUS - LNME Togo")
            ref = item.get("reference_officielle", "")

            if dry_run:
                nb_crees += 1
                continue

            try:
                # Recherche si existe déjà pour éviter doublons
                # Clé basée sur dci + forme + dosage normalisés
                dci_norm = normaliser_chaine(dci)
                existing = Medicament.objects.filter(
                    dci__iexact=dci,
                    forme_pharmaceutique__iexact=forme,
                    dosage__iexact=dosage,
                ).first()

                if existing:
                    existing.nom = nom
                    existing.categorie_therapeutique = cat
                    existing.niveaux_soins = niveaux
                    existing.statut_reglementaire = "liste_essentielle_togo"
                    existing.source_information = source
                    existing.identifiant_externe = ref
                    existing.necessite_validation_manuelle = necessite_validation
                    existing.notes_validation = notes_val
                    existing.est_actif = True
                    existing.save()
                    nb_mis_a_jour += 1
                else:
                    Medicament.objects.create(
                        nom=nom,
                        dci=dci,
                        forme_pharmaceutique=forme,
                        dosage=dosage,
                        categorie_therapeutique=cat,
                        niveaux_soins=niveaux,
                        statut_reglementaire="liste_essentielle_togo",
                        source_information=source,
                        identifiant_externe=ref,
                        necessite_validation_manuelle=necessite_validation,
                        notes_validation=notes_val,
                        est_actif=True,
                    )
                    nb_crees += 1
            except Exception as e:
                nb_erreurs += 1
                self.stderr.write(f"Erreur import sur {dci}: {e}")

        total_en_base = Medicament.objects.filter(est_actif=True).count()
        total_valides_en_base = Medicament.objects.filter(est_actif=True, necessite_validation_manuelle=False).count()
        total_a_valider_en_base = Medicament.objects.filter(est_actif=True, necessite_validation_manuelle=True).count()

        self.stdout.write("\n" + self.style.SUCCESS("=" * 65))
        self.stdout.write(self.style.SUCCESS("COMPTE-RENDU DE L'IMPORTATION :"))
        self.stdout.write(f"  • Entrées créées : {nb_crees}")
        self.stdout.write(f"  • Entrées mises à jour : {nb_mis_a_jour}")
        self.stdout.write(f"  • Erreurs d'insertion : {nb_erreurs}")
        self.stdout.write(f"  • Doublons évités lors du parsing : {len(doublons)}")
        self.stdout.write(f"  • Total catalogue actif en base : {total_en_base}")
        self.stdout.write(f"      - Validés pleinement exploitables : {total_valides_en_base}")
        self.stdout.write(f"      - À valider manuellement (flagués) : {total_a_valider_en_base}")
        self.stdout.write(self.style.SUCCESS("=" * 65))
