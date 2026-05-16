"""arXiv discovery — fetch recent papers in followed categories, rank by
similarity to the user's library, and store a queue for the home page."""
from __future__ import annotations

import json
import sqlite3
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

import arxiv
import numpy as np

from . import embed, storage
from .config import Config
from .db import blob_to_vector


@dataclass
class Candidate:
    arxiv_id: str
    title: str
    authors: list[str]
    published: str       # ISO date
    abstract: str
    score: float
    categories: list[str]
    pdf_url: str
    abs_url: str


def follows_path(cfg: Config) -> Path:
    return cfg.user_dir / "follows.json"


def discover_path(cfg: Config) -> Path:
    return cfg.user_dir / "discover.json"


def list_follows(cfg: Config) -> list[str]:
    p = follows_path(cfg)
    if not p.exists():
        return []
    return json.loads(p.read_text() or "[]")


def set_follows(cfg: Config, categories: list[str]) -> None:
    cfg.user_dir.mkdir(parents=True, exist_ok=True)
    follows_path(cfg).write_text(json.dumps(sorted(set(categories)), indent=2))


def add_follow(cfg: Config, category: str) -> list[str]:
    follows = set(list_follows(cfg))
    follows.add(category.strip())
    out = sorted(follows)
    set_follows(cfg, out)
    return out


def remove_follow(cfg: Config, category: str) -> list[str]:
    follows = set(list_follows(cfg))
    follows.discard(category.strip())
    out = sorted(follows)
    set_follows(cfg, out)
    return out


def interest_vector(conn: sqlite3.Connection) -> np.ndarray | None:
    """Mean of summary_vec across positively-rated papers, then library-wide as fallback."""
    rows = conn.execute(
        """
        SELECT papers.summary_vec
        FROM prefs
        JOIN papers ON papers.id = prefs.paper_id
        WHERE prefs.rating >= 1
          AND papers.summary_vec IS NOT NULL
          AND COALESCE(papers.kind, 'paper') = 'paper'
        """
    ).fetchall()
    if not rows:
        rows = conn.execute(
            "SELECT summary_vec FROM papers "
            "WHERE summary_vec IS NOT NULL AND COALESCE(kind, 'paper') = 'paper'"
        ).fetchall()
    if not rows:
        return None
    matrix = np.stack([blob_to_vector(r["summary_vec"]) for r in rows])
    return matrix.mean(axis=0)


def known_arxiv_ids(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute(
        "SELECT arxiv_id FROM papers WHERE arxiv_id IS NOT NULL AND arxiv_id != ''"
    ).fetchall()
    out: set[str] = set()
    for r in rows:
        out.add(r["arxiv_id"].split("v")[0])  # strip version suffix
    return out


def fetch_candidates(
    categories: list[str],
    *,
    per_category: int = 30,
) -> list[arxiv.Result]:
    """Fetch the most recently submitted papers in each followed category."""
    if not categories:
        return []
    query = " OR ".join(f"cat:{c}" for c in categories)
    search = arxiv.Search(
        query=query,
        max_results=per_category * max(1, len(categories)),
        sort_by=arxiv.SortCriterion.SubmittedDate,
        sort_order=arxiv.SortOrder.Descending,
    )
    return list(arxiv.Client().results(search))


def rank_and_save(
    cfg: Config,
    conn: sqlite3.Connection,
    *,
    per_category: int = 30,
    top_k: int = 12,
) -> list[Candidate]:
    follows = list_follows(cfg)
    if not follows:
        return []
    interest = interest_vector(conn)
    if interest is None:
        return []
    interest = interest / (np.linalg.norm(interest) or 1.0)

    fetched = fetch_candidates(follows, per_category=per_category)
    if not fetched:
        return []

    known = known_arxiv_ids(conn)
    fresh = [r for r in fetched if r.entry_id.split("/")[-1].split("v")[0] not in known]
    if not fresh:
        return []

    texts = [f"{r.title}\n\n{r.summary}" for r in fresh]
    vectors = embed.embed_documents(texts, model=cfg.embed_model)
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    scores = (vectors / norms) @ interest

    order = np.argsort(-scores)[:top_k]
    out: list[Candidate] = []
    for i in order:
        r = fresh[int(i)]
        out.append(Candidate(
            arxiv_id=r.entry_id.split("/")[-1],
            title=r.title.strip().replace("\n", " "),
            authors=[a.name for a in r.authors],
            published=r.published.date().isoformat() if r.published else "",
            abstract=(r.summary or "").strip().replace("\n", " ")[:600],
            score=float(scores[int(i)]),
            categories=list(r.categories),
            pdf_url=r.pdf_url,
            abs_url=r.entry_id,
        ))

    payload = {
        "refreshed_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "follows": follows,
        "candidates": [asdict(c) for c in out],
    }
    cfg.user_dir.mkdir(parents=True, exist_ok=True)
    discover_path(cfg).write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    return out


def load(cfg: Config) -> dict:
    p = discover_path(cfg)
    if not p.exists():
        return {"refreshed_at": None, "follows": [], "candidates": []}
    return json.loads(p.read_text())


def dismiss(cfg: Config, arxiv_id: str) -> None:
    data = load(cfg)
    data["candidates"] = [c for c in data.get("candidates", []) if c.get("arxiv_id") != arxiv_id]
    discover_path(cfg).write_text(json.dumps(data, indent=2, ensure_ascii=False))
