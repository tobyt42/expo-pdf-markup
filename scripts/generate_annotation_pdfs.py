#!/usr/bin/env python3
"""Generate permanent, project-owned annotation regression PDFs for the example.

Requires Pillow >= 10.1 and PyMuPDF:
  python3 -m pip install 'Pillow>=10.1' PyMuPDF
  python3 scripts/generate_annotation_pdfs.py

All scan content (including labels) is rasterized; only text controls contain PDF text.
The media/crop boxes match the native regression fixture's coordinate contract.
"""

from io import BytesIO
from pathlib import Path

import fitz
from PIL import Image, ImageDraw, ImageFont

ASSETS = Path(__file__).resolve().parent.parent / "example" / "assets"
MEDIA = (0, 0, 800, 1000)
CROPPED = (100, 80, 700, 920)
SCAN_CASES = [(CROPPED, rotation) for rotation in (0, 90, 180, 270)] + [
    (MEDIA, 0),
    ((0, 0, 600, 840), 0),
]
TEXT_CASES = [(CROPPED, rotation) for rotation in (0, 90, 180, 270)]


def raster_page(crop: tuple, rotation: int, number: int, text: bool) -> bytes:
    image = Image.new("RGB", (800, 1000), "white")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default(size=20)
    small = ImageFont.load_default(size=16)
    metadata_font = ImageFont.load_default(size=14)
    left, bottom, right, top = crop
    # Pillow's y axis is down; PDF page coordinates are up.
    upper, lower = 1000 - top, 1000 - bottom
    draw.rectangle((left + 10, upper + 10, right - 10, lower - 10), outline="#999999", width=2)
    for x in range(left + 100, right, 100):
        draw.line((x, upper + 100, x, lower - 20), fill="#eeeeee", width=1)
    for y in range(upper + 100, lower - 20, 100):
        draw.line((left + 20, y, right - 20, y), fill="#eeeeee", width=1)
    label = "TEXT CONTROL" if text else "IMAGE-ONLY SCAN"
    header = upper + (80 if upper >= 160 else 20)
    draw.text((left + 25, header), f"{number}. {label} / Rotate {rotation}", fill="black", font=font)
    draw.text((left + 25, header + 25), f"MediaBox {MEDIA}", fill="#444444", font=metadata_font)
    draw.text((left + 25, header + 45), f"CropBox {crop}", fill="#444444", font=metadata_font)
    # Same asymmetric raster anchors as the native fixture (top-left raster coords).
    draw.rectangle((150, 170, 179, 219), fill="#2060d0")
    draw.rectangle((490, 650, 549, 669), fill="#208040")
    draw.text((195, 180), "Ink around the blue anchor", fill="black", font=small)
    draw.text((left + 25, upper + 240), "Drag a highlight across this area", fill="black", font=font)
    draw.text((left + 25, upper + 310), "Drag an underline below this area", fill="black", font=font)
    for y in range(upper + 385, upper + 426, 10):
        draw.line((left + 30, y, right - 30, y), fill="#444444", width=1)
    draw.text((left + 25, lower - 160), "Place text and stamps near the edges", fill="black", font=font)
    draw.text((left + 25, lower - 120), "Move / erase: outlines must follow visible marks", fill="black", font=small)
    draw.text((left + 25, lower - 85), "Use View to navigate or zoom", fill="black", font=small)
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def generate(name: str, cases: list, text: bool) -> None:
    document = fitz.open()
    for number, (crop, rotation) in enumerate(cases, start=1):
        page = document.new_page(width=800, height=1000)
        page.insert_image(page.rect, stream=raster_page(crop, rotation, number, text))
        if text:
            page.insert_text((140, 620), "Selectable text: highlight or underline this sentence.", fontsize=17)
        # PyMuPDF expresses CropBox in unrotated, top-left page coordinates.
        left, bottom, right, top = crop
        page.set_cropbox(fitz.Rect(left, 1000 - top, right, 1000 - bottom))
        page.set_rotation(rotation)
    document.set_metadata({"title": name, "author": "expo-pdf-markup synthetic fixtures"})
    (ASSETS / name).write_bytes(document.tobytes(garbage=4, deflate=True, no_new_id=True))
    document.close()


if __name__ == "__main__":
    generate("annotation-scan-regression.pdf", SCAN_CASES, text=False)
    generate("annotation-text-regression.pdf", TEXT_CASES, text=True)
