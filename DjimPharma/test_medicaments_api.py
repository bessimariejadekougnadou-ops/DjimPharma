import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.test import Client

client = Client()

test_queries = [
    'paracetamol',
    'PARACETAMOL',
    'paracétamol',
    'amoxicilline',
    'AMOXICILLINE 500',
    'injectable',
    'inhalation',
    'artesunate',
    'ibuprofene',
    'lidocaine',
    'morphine',
]

print("=" * 60)
print("TEST DE L'API DE RECHERCHE DU CATALOGUE DJIMPHARMA")
print("=" * 60)

for q in test_queries:
    resp = client.get(f'/api/medicaments/?q={q}')
    if resp.status_code == 200:
        data = resp.json()
        count = data.get('count', 0)
        results = data.get('results', [])
        top_name = results[0]['nom'] if results else 'Aucun'
        statut = results[0]['disponibilite_statut'] if results else '-'
        libelle = results[0]['disponibilite_libelle'] if results else '-'
        print(f"Query: '{q}' -> {count} trouvés. 1er: {top_name} [{statut} : {libelle}]")
    else:
        print(f"Query: '{q}' -> Erreur HTTP {resp.status_code}: {resp.content}")

# Test de la fiche détaillée d'un médicament
detail_resp = client.get('/api/medicaments/1/')
print("\n" + "=" * 60)
print("TEST FICHE DETAILLEE MEDICAMENT #1 :")
if detail_resp.status_code == 200:
    d = detail_resp.json()
    print("Nom:", d['nom'])
    print("DCI:", d['dci'])
    print("Forme:", d['forme_pharmaceutique'])
    print("Dosage:", d['dosage'])
    print("Classe:", d['categorie_therapeutique'])
    print("Statut réglementaire:", d['statut_reglementaire_display'])
    print("Source:", d['source_information'])
    print("Disponibilité:", d['disponibilite_statut'], "-", d['disponibilite_libelle'])
    print("Message au patient:", d['disponibilite_message'])
    print("Pharmacies de contact proposées:", len(d.get('pharmacies_contact_recommandees', [])))
else:
    print("Erreur HTTP:", detail_resp.status_code, detail_resp.content)
