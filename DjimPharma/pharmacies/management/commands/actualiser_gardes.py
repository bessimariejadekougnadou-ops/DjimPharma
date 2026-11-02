from django.core.management.base import BaseCommand
from pharmacies.services.garde_service import GardeService


class Command(BaseCommand):
    help = "Vérifie et actualise automatiquement le statut de garde des pharmacies au Togo (activation/expiration)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--silent",
            action="store_true",
            help="Exécution silencieuse pour les tâches planifiées / crons.",
        )

    def handle(self, *args, **options):
        silent = options.get("silent", False)
        if not silent:
            self.stdout.write(self.style.NOTICE("Démarrage du recalcul des pharmacies de garde..."))

        rapport = GardeService.verifier_et_actualiser_toutes_les_gardes()

        if not silent:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Succès ! {rapport['statuts_modifies']} statuts modifiés, "
                    f"{rapport['gardes_expirees']} gardes expirées, "
                    f"{rapport['total_gardes_actives']} pharmacies de garde actuellement actives."
                )
            )
