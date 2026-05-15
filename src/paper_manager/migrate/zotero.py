from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator

DEFAULT_ZOTERO_STORAGE = Path(
    "~/Library/Mobile Documents/com~apple~CloudDocs/zoteto_storage"
).expanduser()


@dataclass
class MigrationProgress:
    index: int
    total: int
    pdf: Path
    title: str
    paper_id: str
    state: str  # "new" | "duplicate" | "error"
    error: str | None = None


def find_pdfs(zotero_root: Path) -> list[Path]:
    if not zotero_root.exists():
        return []
    pdfs: list[Path] = []
    for child in sorted(zotero_root.iterdir()):
        if not child.is_dir():
            continue
        for pdf in sorted(child.glob("*.pdf")):
            pdfs.append(pdf)
    return pdfs


def migrate(
    zotero_root: Path,
    *,
    ingest_one: Callable[[Path], tuple[str, str, bool]],
    on_progress: Callable[[MigrationProgress], None] | None = None,
) -> Iterator[MigrationProgress]:
    """Iterate Zotero storage and ingest each PDF.

    `ingest_one(pdf)` should return (paper_id, title, is_new). On exception,
    we record the failure and continue.
    """
    pdfs = find_pdfs(zotero_root)
    total = len(pdfs)
    for i, pdf in enumerate(pdfs, start=1):
        try:
            paper_id, title, is_new = ingest_one(pdf)
            prog = MigrationProgress(
                index=i,
                total=total,
                pdf=pdf,
                title=title,
                paper_id=paper_id,
                state="new" if is_new else "duplicate",
            )
        except Exception as e:
            prog = MigrationProgress(
                index=i,
                total=total,
                pdf=pdf,
                title=pdf.stem,
                paper_id="",
                state="error",
                error=str(e),
            )
        if on_progress:
            on_progress(prog)
        yield prog
