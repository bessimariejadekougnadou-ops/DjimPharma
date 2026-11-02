"""
Affine le fichier catalogue_togo_officiel.json :
- Filtre les en-têtes résiduels et notes de bas de page des entrées à valider.
- Vérifie la cohérence des noms et DCIs.
- Re-calcule les statistiques de qualité.
"""
import json
import re
import unicodedata

def normaliser_chaine(texte: str) -> str:
    if not texte:
        return ""
    texte_sans_accents = "".join(
        c for c in unicodedata.normalize("NFD", texte)
        if unicodedata.category(c) != "Mn"
    )
    return " ".join(texte_sans_accents.lower().split())

with open("medicaments/data/catalogue_togo_officiel.json", "r", encoding="utf-8") as f:
    data = json.load(f)

valides_init = data["medicaments_valides"]
a_valider_init = data["medicaments_a_valider"]
doublons = data["doublons_detectes"]

valides_propres = []
a_valider_propres = []
rejets_parasites = []

# Filtrer et nettoyer les valides
seen_keys = set()
for m in valides_init:
    dci = m["dci"].strip()
    forme = m.get("forme_pharmaceutique", "").strip()
    dosage = m.get("dosage", "").strip()

    # Nettoyage préfixe
    dci = re.sub(r'^\d+\s*[-.)]?\s*', '', dci)
    dci = re.sub(r'[*†‡]', '', dci).strip()

    # Si c'est manifestement une note ou titre de section
    if re.match(r'^\(?\s*(?:[xX]|\*|\d+)\s*\)?\s*(?:Si\s+|Niveau\s+|La\s+prescription|Sous\s+r|r[eé]serve|uniquement)', dci, re.I):
        rejets_parasites.append({"dci": dci, "motif": "Note réglementaire ou consigne d'usage"})
        continue

    if len(dci) < 3 or not re.search(r'[a-zA-ZÀ-ÿ]', dci):
        rejets_parasites.append({"dci": dci, "motif": "Chaîne trop courte ou sans lettres"})
        continue

    # Clé normalisée
    key = (normaliser_chaine(dci), normaliser_chaine(forme), normaliser_chaine(dosage))
    if key in seen_keys:
        doublons.append({"dci": dci, "forme": forme, "dosage": dosage, "source": m["source_information"]})
        continue

    seen_keys.add(key)
    m["dci"] = dci
    m["nom"] = f"{dci} {dosage} ({forme})".strip() if (forme and dosage) else f"{dci} {dosage or forme}".strip()
    valides_propres.append(m)

# Filtrer a_valider : séparer les vrais médicaments incomplets des titres/notes
for m in a_valider_init:
    dci = m["dci"].strip()
    # Notes de bas de page ou en-têtes
    if re.match(r'^\(?\s*(?:[xX]|\*|\d+)\s*\)?\s*(?:Si\s+|Niveau\s+|La\s+prescription|Sous\s+r|r[eé]serve|uniquement)', dci, re.I):
        rejets_parasites.append({"dci": dci, "motif": "Note réglementaire ou consigne d'usage"})
        continue
    if re.match(r'^\d+(\.\d+)*\s+[A-ZÀ-ÿ]', dci) or (dci.isupper() and len(dci) > 15 and not any(kw in dci for kw in ['MG', 'ML', 'G', '%'])):
        rejets_parasites.append({"dci": dci, "motif": "Titre de section ou chapitre"})
        continue
    if len(dci) < 3 or not re.search(r'[a-zA-ZÀ-ÿ]', dci):
        rejets_parasites.append({"dci": dci, "motif": "Caractères invalides"})
        continue

    # Clé
    key = (normaliser_chaine(dci), normaliser_chaine(m.get("forme_pharmaceutique", "")), normaliser_chaine(m.get("dosage", "")))
    if key in seen_keys:
        continue
    seen_keys.add(key)
    a_valider_propres.append(m)

stats = {
    "total_lignes_brutes_ocr": data["statistiques"]["total_lignes_brutes_ocr"],
    "total_medicaments_valides_exploites": len(valides_propres),
    "total_a_valider_manuellement": len(a_valider_propres),
    "total_lignes_parasites_ecartees": len(rejets_parasites),
    "total_doublons_detectes": len(doublons),
    "source": "Arrêté N° 147/2021/MSHPAUS - Ministère de la Santé du Togo (LNME 2021)",
    "statut_reglementaire": "liste_essentielle_togo",
    "mention_amm": "Non attribué automatiquement - Inscription LNME vérifiée",
}

output = {
    "statistiques": stats,
    "medicaments_valides": valides_propres,
    "medicaments_a_valider": a_valider_propres,
    "lignes_parasites_ecartees": rejets_parasites,
    "doublons_detectes": doublons,
}

with open("medicaments/data/catalogue_togo_officiel.json", "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print("Affinage terminé avec succès :")
print(f"  • Médicaments validés exploitables : {len(valides_propres)}")
print(f"  • Médicaments à valider manuellement : {len(a_valider_propres)}")
print(f"  • Lignes parasites écartées (notes/titres) : {len(rejets_parasites)}")
print(f"  • Doublons identifiés : {len(doublons)}")
