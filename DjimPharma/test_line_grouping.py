"""
Test d'extraction et de parsing de tableau OCR sur les pages 4 et 5.
"""
import os
import re
from rapidocr_onnxruntime import RapidOCR

engine = RapidOCR()

def parse_page(image_path):
    result, _ = engine(image_path)
    if not result:
        return []

    # result: list of [box, text, score]
    # box: [[x1, y1], [x2, y2], [x3, y3], [x4, y4]]
    boxes_with_info = []
    for box, text, score in result:
        try:
            score_val = float(score)
        except Exception:
            score_val = 0.8
        y_top = box[0][1]
        x_left = box[0][0]
        y_bottom = box[2][1]
        boxes_with_info.append({
            'text': text.strip(),
            'x': x_left,
            'y': y_top,
            'y_bottom': y_bottom,
            'score': score_val,
        })

    # Trier par y
    boxes_with_info.sort(key=lambda b: (b['y'], b['x']))

    # Regrouper en lignes selon y (seuil 14 pixels)
    lines = []
    current_line = []
    current_y = -999

    for b in boxes_with_info:
        if current_y == -999 or abs(b['y'] - current_y) <= 14:
            current_line.append(b)
            # moyenne pondérée de y
            current_y = sum(item['y'] for item in current_line) / len(current_line)
        else:
            if current_line:
                current_line.sort(key=lambda item: item['x'])
                lines.append(current_line)
            current_line = [b]
            current_y = b['y']

    if current_line:
        current_line.sort(key=lambda item: item['x'])
        lines.append(current_line)

    return lines

print("Parsing page 4...")
lines = parse_page('medicaments/data/page_4.png')
for i, line in enumerate(lines):
    line_text = " | ".join(f"[{b['x']:.0f}] {b['text']}" for b in line)
    print(f"L{i:02d}: {line_text}")
