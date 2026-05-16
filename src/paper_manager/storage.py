from __future__ import annotations

import hashlib
import json
import shutil
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .config import Config


@dataclass
class PaperMeta:
    id: str
    title: str
    authors: list[str]
    year: int | None
    venue: str | None
    doi: str | None
    arxiv_id: str | None
    added_at: str
    sha256: str
    source: str
    kind: str = "paper"           # 'paper' | 'book' | 'report'
    pages: int | None = None
    user_tags: list[str] = field(default_factory=list)
    auto: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "PaperMeta":
        return cls(
            id=data["id"],
            title=data.get("title", "Untitled"),
            authors=data.get("authors", []),
            year=data.get("year"),
            venue=data.get("venue"),
            doi=data.get("doi"),
            arxiv_id=data.get("arxiv_id"),
            added_at=data.get("added_at", now_iso()),
            sha256=data.get("sha256", ""),
            source=data.get("source", "manual"),
            kind=data.get("kind", "paper"),
            pages=data.get("pages"),
            user_tags=data.get("user_tags", []),
            auto=data.get("auto", {}),
        )


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def paper_id_from_sha(sha: str) -> str:
    return sha[:12]


def paper_dir(cfg: Config, paper_id: str) -> Path:
    return cfg.library_dir / paper_id


def pdf_path(cfg: Config, paper_id: str) -> Path:
    return paper_dir(cfg, paper_id) / "paper.pdf"


def metadata_path(cfg: Config, paper_id: str) -> Path:
    return paper_dir(cfg, paper_id) / "metadata.json"


def summary_path(cfg: Config, paper_id: str) -> Path:
    return paper_dir(cfg, paper_id) / "summary.md"


def text_path(cfg: Config, paper_id: str) -> Path:
    return paper_dir(cfg, paper_id) / "text.txt"


def chunks_path(cfg: Config, paper_id: str) -> Path:
    return paper_dir(cfg, paper_id) / "chunks.json"


def figures_dir(cfg: Config, paper_id: str) -> Path:
    return paper_dir(cfg, paper_id) / "figures"


def ensure_dirs(cfg: Config) -> None:
    cfg.library_dir.mkdir(parents=True, exist_ok=True)
    cfg.inbox_dir.mkdir(parents=True, exist_ok=True)
    cfg.user_dir.mkdir(parents=True, exist_ok=True)
    cfg.local_root.mkdir(parents=True, exist_ok=True)
    cfg.chats_dir.mkdir(parents=True, exist_ok=True)


def copy_pdf(cfg: Config, src: Path, paper_id: str) -> Path:
    pdir = paper_dir(cfg, paper_id)
    pdir.mkdir(parents=True, exist_ok=True)
    dest = pdf_path(cfg, paper_id)
    if src.resolve() != dest.resolve():
        shutil.copy2(src, dest)
    return dest


def write_metadata(cfg: Config, meta: PaperMeta) -> None:
    metadata_path(cfg, meta.id).write_text(
        json.dumps(meta.to_dict(), indent=2, ensure_ascii=False)
    )


def read_metadata(cfg: Config, paper_id: str) -> PaperMeta:
    return PaperMeta.from_dict(json.loads(metadata_path(cfg, paper_id).read_text()))


def write_text(cfg: Config, paper_id: str, text: str) -> None:
    text_path(cfg, paper_id).write_text(text)


def read_text(cfg: Config, paper_id: str) -> str:
    return text_path(cfg, paper_id).read_text()


def write_summary(cfg: Config, paper_id: str, summary: str) -> None:
    summary_path(cfg, paper_id).write_text(summary)


def read_summary(cfg: Config, paper_id: str) -> str:
    return summary_path(cfg, paper_id).read_text()


def write_chunks(cfg: Config, paper_id: str, chunks: list[dict]) -> None:
    chunks_path(cfg, paper_id).write_text(json.dumps(chunks, ensure_ascii=False))


def read_chunks(cfg: Config, paper_id: str) -> list[dict]:
    return json.loads(chunks_path(cfg, paper_id).read_text())


def list_paper_ids(cfg: Config) -> list[str]:
    if not cfg.library_dir.exists():
        return []
    return sorted(
        d.name
        for d in cfg.library_dir.iterdir()
        if d.is_dir() and (d / "metadata.json").exists()
    )


def delete_paper(cfg: Config, paper_id: str) -> bool:
    """Remove a paper's directory (PDF, summary, figures, chunks) from iCloud.
    Caller is responsible for cleaning the SQLite rows separately."""
    pdir = paper_dir(cfg, paper_id)
    if not pdir.exists():
        return False
    shutil.rmtree(pdir)
    return True
