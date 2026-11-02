"""
Script de secours pour restaurer les 660 stocks de démonstration en cas de besoin.
Usage : python restaurer_stocks_secours.py
"""
import os
import sys
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.core.management import call_command
from stocks.models import StockPharmacie

fixture_path = os.path.join(os.path.dirname(__file__), 'stocks', 'fixtures', 'stocks_demo_backup.json')

if not os.path.exists(fixture_path):
    print(f"Erreur: Fichier de sauvegarde introuvable : {fixture_path}")
    sys.exit(1)

print(f"Restauration depuis {fixture_path}...")
call_command('loaddata', fixture_path)
print(f"Restauration terminée avec succès. Total stocks actuels: {StockPharmacie.objects.count()}")
