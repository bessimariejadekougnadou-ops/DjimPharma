"""
Script d'extraction complet du catalogue officiel LNME Togo 2021 (Adultes Parties 1 et 2).
Extrait par OCR les tableaux de l'Arrêté N° 147/2021/MSHPAUS, effectue le contrôle qualité,
distingue les données validées des données nécessitant validation manuelle, et produit
un rapport d'audit détaillé en JSON.
"""
import os
import re
import json
import unicodedata
import pymupdf
from rapidocr_onnxruntime import RapidOCR

engine = RapidOCR()

def normaliser_chaine(texte: str) -> str:
    if not texte:
        return ""
    texte_sans_accents = "".join(
        c for c in unicodedata.normalize("NFD", texte)
        if unicodedata.category(c) != "Mn"
    )
    return " ".join(texte_sans_accents.lower().split())

def clean_text(t: str) -> str:
    t = re.sub(r'[\r\n]+', ' ', t)
    t = re.sub(r'\s+', ' ', t)
    return t.strip()

def is_section_header(text: str) -> bool:
    # Ex: "1. ANESTHESIQUES...", "1.1 ANESTHESIQUES GENERAUX", "1.1.1 Medicaments...", "2. ANALGESIQUES..."
    return bool(re.match(r'^\d+(\.\d+)*\s+[A-ZÀ-ÿ]', text)) or bool(re.match(r'^[A-ZÀ-ÿ\s,]{8,}$', text) and any(kw in text.upper() for kw in ['ANESTHESIQUES', 'ANTIBACTERIENS', 'ANTIPARASITAIRES', 'MEDICAMENTS', 'CARDIO', 'DERMATO', 'GASTRO', 'PSYCHO', 'HORMONES', 'SANG', 'SOLUTES', 'VITAMINES']))

def parse_boxes_into_lines(ocr_result):
    if not ocr_result:
        return []

    boxes = []
    for box, text, score in ocr_result:
        try:
            score_val = float(score)
        except Exception:
            score_val = 0.8
        boxes.append({
            'text': clean_text(text),
            'x': box[0][0],
            'y': box[0][1],
            'score': score_val
        })

    boxes.sort(key=lambda b: (b['y'], b['x']))

    lines = []
    curr_line = []
    curr_y = -999

    for b in boxes:
        if curr_y == -999 or abs(b['y'] - curr_y) <= 13:
            curr_line.append(b)
            curr_y = sum(item['y'] for item in curr_line) / len(curr_line)
        else:
            if curr_line:
                curr_line.sort(key=lambda item: item['x'])
                lines.append(curr_line)
            curr_line = [b]
            curr_y = b['y']

    if curr_line:
        curr_line.sort(key=lambda item: item['x'])
        lines.append(curr_line)

    return lines

def extract_pdf(pdf_path, start_page=0, end_page=None, doc_label="part1"):
    doc = pymupdf.open(pdf_path)
    total_pages = len(doc)
    if end_page is None or end_page > total_pages:
        end_page = total_pages

    print(f"\nTraitement de {pdf_path} (Pages {start_page + 1} à {end_page} sur {total_pages})...")

    current_category = "Médicaments essentiels"
    all_raw_rows = []

    for page_idx in range(start_page, end_page):
        page = doc[page_idx]
        pix = page.get_pixmap(dpi=200)
        img_temp = f"medicaments/data/temp_{doc_label}_p{page_idx + 1}.png"
        pix.save(img_temp)

        ocr_result, _ = engine(img_temp)
        lines = parse_boxes_into_lines(ocr_result)

        if os.path.exists(img_temp):
            os.remove(img_temp)

        print(f"  Page {page_idx + 1}/{total_pages} : {len(lines)} lignes OCR détectées.")

        for line in lines:
            line_full = " ".join(b['text'] for b in line)

            # En-têtes à ignorer
            if any(h in line_full.upper() for h in ['NIVEAU D\'UTILISATION', 'LISTE NATIONALE DES ME', 'NIVEAUD\'UTILISATION', '1: ASC', '2 : USPI', '3:USPII', 'HD IL']):
                continue
            if re.match(r'^(DCI|FORME|DOSAGE)\b', line_full.upper()):
                continue

            # Titres de catégories / sous-catégories
            first_box = line[0]
            if is_section_header(line_full) or (first_box['x'] < 300 and is_section_header(first_box['text'])):
                current_category = line_full.strip()
                continue

            # Traitement d'une ligne de médicament
            # Partitionnement par colonnes :
            # num : x < 80
            # dci : 75 <= x < 350
            # forme : 350 <= x < 500
            # dosage : 500 <= x < 720
            # niveaux : x >= 720
            num_text = ""
            dci_texts = []
            forme_texts = []
            dosage_texts = []
            niveaux_texts = []

            for b in line:
                t = b['text']
                x = b['x']
                if x < 80 and re.match(r'^\d+$', t):
                    num_text = t
                elif x < 350:
                    dci_texts.append(t)
                elif 350 <= x < 500:
                    forme_texts.append(t)
                elif 500 <= x < 720:
                    dosage_texts.append(t)
                else:
                    niveaux_texts.append(t)

            dci_str = clean_text(" ".join(dci_texts))
            forme_str = clean_text(" ".join(forme_texts))
            dosage_str = clean_text(" ".join(dosage_texts))
            niveaux_str = clean_text(" ".join(niveaux_texts))

            # Ignorer les lignes parasites ou de notes de bas de page
            if not dci_str and not forme_str and not dosage_str:
                continue
            if dci_str.startswith('*') or dci_str.lower().startswith('liste complementaire'):
                continue

            all_raw_rows.append({
                'source_doc': f"{doc_label} p.{page_idx + 1}",
                'category': current_category,
                'num': num_text,
                'dci': dci_str,
                'forme': forme_str,
                'dosage': dosage_str,
                'niveaux': niveaux_str,
            })

    return all_raw_rows

def assemble_and_validate(raw_rows):
    """
    Fusionne les lignes multi-lignes et applique le contrôle qualité.
    """
    assembled = []
    current_entry = None

    for row in raw_rows:
        dci = row['dci']
        forme = row['forme']
        dosage = row['dosage']

        # Si la ligne a une nouvelle DCI (lettres >= 3 et pas que des symboles)
        has_new_dci = bool(dci and re.search(r'[a-zA-ZÀ-ÿ]{3,}', dci))

        if has_new_dci:
            if current_entry:
                assembled.append(current_entry)
            current_entry = {
                'dci': dci,
                'forme': forme,
                'dosage': dosage,
                'niveaux': row['niveaux'],
                'categorie': row['category'],
                'source': row['source_doc'],
                'numero_ligne': row['num'],
            }
        else:
            # Ligne de continuation
            if current_entry:
                if dci and not forme and not dosage:
                    current_entry['dci'] += " " + dci
                if forme:
                    current_entry['forme'] = (current_entry['forme'] + " " + forme).strip()
                if dosage:
                    current_entry['dosage'] = (current_entry['dosage'] + " " + dosage).strip()
                if row['niveaux']:
                    current_entry['niveaux'] = (current_entry['niveaux'] + " " + row['niveaux']).strip()

    if current_entry:
        assembled.append(current_entry)

    # Nettoyage et contrôle qualité
    valid_entries = []
    manual_check_entries = []
    seen_keys = {}
    duplicates = []

    for item in assembled:
        dci = clean_text(item['dci'])
        # Retirer les astérisques ou numéros résiduels au début
        dci = re.sub(r'^\d+\s*[-.)]?\s*', '', dci)
        dci = re.sub(r'[*†‡]', '', dci).strip()

        forme = clean_text(item['forme'])
        dosage = clean_text(item['dosage'])
        cat = clean_text(item['categorie'])
        niveaux = clean_text(item['niveaux'])

        # Clé unique de déduplication normalisée
        key = (
            normaliser_chaine(dci),
            normaliser_chaine(forme),
            normaliser_chaine(dosage)
        )

        if not dci or len(dci) < 3 or not re.search(r'[a-zA-ZÀ-ÿ]', dci):
            item['motif_rejet'] = "DCI vide ou non alphabétique"
            manual_check_entries.append(item)
            continue

        # Vérifier si c'est un doublon
        if key in seen_keys:
            duplicates.append({
                'dci': dci,
                'forme': forme,
                'dosage': dosage,
                'premiere_source': seen_keys[key]['source'],
                'source_doublon': item['source']
            })
            continue

        # Déterminer la qualité de l'entrée
        is_complete = bool(forme or dosage)
        has_suspect_chars = bool(re.search(r'[{}\[\]<>]', dci))

        record = {
            'nom': f"{dci} {dosage} ({forme})".strip() if (forme and dosage) else f"{dci} {dosage or forme}".strip(),
            'dci': dci,
            'forme_pharmaceutique': forme,
            'dosage': dosage,
            'categorie_therapeutique': cat,
            'niveaux_soins': niveaux,
            'statut_reglementaire': 'liste_essentielle_togo', # IMPORTANT: pas d'attribution automatique d'AMM
            'source_information': f"Arrêté N° 147/2021/MSHPAUS - LNME Togo ({item['source']})",
            'reference_officielle': f"LNME-TOGO-2021-{item['numero_ligne'] or 'REF'}",
            'necessite_validation_manuelle': not is_complete or has_suspect_chars,
            'notes_validation': "Forme ou dosage à préciser par contrôle pharmacologique" if not is_complete else ("Caractères suspects dans DCI" if has_suspect_chars else "")
        }

        seen_keys[key] = item

        if record['necessite_validation_manuelle']:
            manual_check_entries.append(record)
        else:
            valid_entries.append(record)

    return valid_entries, manual_check_entries, duplicates

def main():
    print("=" * 60)
    print("EXTRACTION DU CATALOGUE OFFICIEL DES MEDICAMENTS DU TOGO (2021)")
    print("Arrêté N° 147/2021/MSHPAUS / Liste Nationale des Médicaments Essentiels")
    print("=" * 60)

    # Part 1 : Tableaux de la page 4 à la page 13 (index 3 à 13)
    p1_rows = extract_pdf("medicaments/data/togo-neml_2021_adult_part1.pdf", start_page=3, end_page=13, doc_label="adultes_part1")

    # Part 2 : Tableaux de la page 1 à la page 12 (index 0 à 12)
    p2_rows = extract_pdf("medicaments/data/adult_part2.pdf", start_page=0, end_page=12, doc_label="adultes_part2")

    all_rows = p1_rows + p2_rows
    print(f"\nTotal lignes brutes extraites par OCR : {len(all_rows)}")

    valides, a_valider, doublons = assemble_and_validate(all_rows)

    stats = {
        'total_lignes_brutes_ocr': len(all_rows),
        'total_medicaments_valides_exploites': len(valides),
        'total_a_valider_manuellement': len(a_valider),
        'total_doublons_detectes': len(doublons),
        'source': "Arrêté N° 147/2021/MSHPAUS (Ministère de la Santé du Togo)",
        'statut_reglementaire': "liste_essentielle_togo",
        'mention_amm': "Non attribué automatiquement - Inscription LNME vérifiée"
    }

    output_data = {
        'statistiques': stats,
        'medicaments_valides': valides,
        'medicaments_a_valider': a_valider,
        'doublons_detectes': doublons,
    }

    out_file = "medicaments/data/catalogue_togo_officiel.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 60)
    print("BILAN DU CONTRÔLE QUALITÉ & EXTRACTION :")
    print(f"  • Médicaments exploitables et validés : {len(valides)}")
    print(f"  • Entrées nécessitant validation manuelle : {len(a_valider)}")
    print(f"  • Doublons identifiés et fusionnés : {len(doublons)}")
    print(f"  • Fichier JSON sauvegardé : {out_file}")
    print("=" * 60)

if __name__ == '__main__':
    main()
