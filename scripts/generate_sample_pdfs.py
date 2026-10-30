#!/usr/bin/env python3
"""Generate the example app's book mode sample PDFs (stdlib only).

Writes example/assets/book-sample.pdf (6 pages) and example/assets/single-page.pdf (1 page).
Each page shows a large page number, a staff of lines and a coloured edge band, so a page
turn is easy to see. Re-run with: python3 scripts/generate_sample_pdfs.py
"""

import os

WIDTH, HEIGHT = 595, 842  # A4 portrait, in points
COLOURS = [
    (0.85, 0.20, 0.20),
    (0.95, 0.55, 0.10),
    (0.20, 0.65, 0.30),
    (0.15, 0.45, 0.85),
    (0.50, 0.30, 0.80),
    (0.40, 0.40, 0.40),
]


def page_content(number: int, total: int) -> bytes:
    r, g, b = COLOURS[(number - 1) % len(COLOURS)]
    ops = [
        # Coloured band down both edges.
        f"{r} {g} {b} rg",
        f"0 0 24 {HEIGHT} re f",
        f"{WIDTH - 24} 0 24 {HEIGHT} re f",
        # Large page number.
        "0 0 0 rg",
        "BT /F1 160 Tf",
        f"{WIDTH / 2 - (45 if number < 10 else 90)} {HEIGHT / 2 + 40} Td",
        f"({number}) Tj ET",
        "BT /F1 28 Tf",
        f"{WIDTH / 2 - 70} {HEIGHT / 2 - 10} Td",
        f"(Page {number} of {total}) Tj ET",
        # Two five-line staves, for trying out markup.
        "0.6 w 0 0 0 RG",
    ]
    for top in (260, 160):
        for line in range(5):
            y = top - line * 10
            ops.append(f"60 {y} m {WIDTH - 60} {y} l S")
    return "\n".join(ops).encode("latin-1")


def build_pdf(total: int) -> bytes:
    objects: list[bytes] = []

    def add(body: bytes) -> int:
        objects.append(body)
        return len(objects)

    catalog = add(b"")  # placeholder, filled once the page tree exists
    pages = add(b"")
    font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    page_ids = []
    for number in range(1, total + 1):
        stream = page_content(number, total)
        content = add(
            b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream"
        )
        page_ids.append(
            add(
                (
                    f"<< /Type /Page /Parent {pages} 0 R /MediaBox [0 0 {WIDTH} {HEIGHT}] "
                    f"/Resources << /Font << /F1 {font} 0 R >> >> /Contents {content} 0 R >>"
                ).encode("latin-1")
            )
        )

    kids = " ".join(f"{pid} 0 R" for pid in page_ids)
    objects[pages - 1] = f"<< /Type /Pages /Kids [{kids}] /Count {total} >>".encode("latin-1")
    objects[catalog - 1] = f"<< /Type /Catalog /Pages {pages} 0 R >>".encode("latin-1")

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for index, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{index} 0 obj\n".encode("latin-1") + body + b"\nendobj\n"

    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode("latin-1")
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode("latin-1")
    out += (
        f"trailer\n<< /Size {len(objects) + 1} /Root {catalog} 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode("latin-1")
    return bytes(out)


def main() -> None:
    assets = os.path.join(os.path.dirname(__file__), "..", "example", "assets")
    for name, total in (("book-sample.pdf", 6), ("single-page.pdf", 1)):
        with open(os.path.join(assets, name), "wb") as handle:
            handle.write(build_pdf(total))


if __name__ == "__main__":
    main()
