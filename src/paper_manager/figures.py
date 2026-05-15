"""Extract figures (embedded raster images) from PDFs.

For each PDF we pull the embedded images, filter out tiny decorations, and write
them to `<paper_dir>/figures/figure-NNN.<ext>` along with a small JSON manifest.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import fitz  # PyMuPDF

# Skip images smaller than this on either axis — almost always logos, icons,
# section ornaments, equation glyphs.
MIN_DIM = 180
# Total pixel area to skip — catches wide-but-short thin strips, page furniture.
MIN_AREA = 60_000
# Cap how many figures we save per paper (some old papers embed dozens of
# decorative graphics).
MAX_FIGURES = 24


@dataclass
class Figure:
    index: int
    filename: str
    page: int
    width: int
    height: int


def extract(pdf_path: Path, out_dir: Path) -> list[Figure]:
    """Extract figures into `out_dir`. Returns the manifest."""
    out_dir.mkdir(parents=True, exist_ok=True)
    figures: list[Figure] = []
    seen_hashes: set[str] = set()

    doc = fitz.open(str(pdf_path))
    try:
        for page_num, page in enumerate(doc, start=1):
            if len(figures) >= MAX_FIGURES:
                break
            for img in page.get_images(full=True):
                xref = img[0]
                try:
                    base_image = doc.extract_image(xref)
                except Exception:
                    continue
                image_bytes = base_image.get("image")
                ext = base_image.get("ext", "png")
                if not image_bytes:
                    continue

                width = base_image.get("width", 0)
                height = base_image.get("height", 0)
                if width < MIN_DIM or height < MIN_DIM:
                    continue
                if width * height < MIN_AREA:
                    continue

                content_hash = hashlib.sha256(image_bytes).hexdigest()
                if content_hash in seen_hashes:
                    continue
                seen_hashes.add(content_hash)

                idx = len(figures) + 1
                filename = f"figure-{idx:03d}.{ext}"
                (out_dir / filename).write_bytes(image_bytes)
                figures.append(Figure(
                    index=idx,
                    filename=filename,
                    page=page_num,
                    width=width,
                    height=height,
                ))
                if len(figures) >= MAX_FIGURES:
                    break
    finally:
        doc.close()

    manifest = [
        {"index": f.index, "filename": f.filename, "page": f.page, "width": f.width, "height": f.height}
        for f in figures
    ]
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return figures


def load_manifest(figures_dir: Path) -> list[dict]:
    manifest_path = figures_dir / "manifest.json"
    if not manifest_path.exists():
        return []
    return json.loads(manifest_path.read_text())
