from django.core.management.base import BaseCommand
from integrations.services.togo_garde_sync import TogoPharmacieGardeService


class Command(BaseCommand):
    help = "Synchronise les pharmacies de garde au Togo (API Kondjigbale / ONPT)"

    def handle(self, *args, **options):
        self.stdout.write("Demarrage de la synchronisation des pharmacies de garde du Togo...")
        rapport = TogoPharmacieGardeService.synchroniser_gardes()
        self.stdout.write(self.style.SUCCESS(f"Source : {rapport['source']}"))
        self.stdout.write(self.style.SUCCESS(f"Resultat : {rapport['message']}"))
        self.stdout.write(f"Pharmacies de garde : {', '.join(rapport['pharmacies_de_garde'])}")
