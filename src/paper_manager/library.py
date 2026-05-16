"""Mutation helpers for the library — used by both the CLI and the /manage page."""
from __future__ import annotations

import json
import sqlite3

from . import storage
from .config import Config

VALID_KINDS = {"paper", "book", "report"}


class LibraryError(RuntimeError):
    pass


def delete(cfg: Config, conn: sqlite3.Connection, paper_id: str) -> str:
    """Remove a paper from iCloud + SQLite. Returns the deleted paper's title."""
    row = conn.execute("SELECT title FROM papers WHERE id = ?", (paper_id,)).fetchone()
    title = row["title"] if row else paper_id
    storage.delete_paper(cfg, paper_id)
    with conn:
        conn.execute("DELETE FROM chunks WHERE paper_id = ?", (paper_id,))
        conn.execute("DELETE FROM chunks_fts WHERE paper_id = ?", (paper_id,))
        conn.execute("DELETE FROM prefs WHERE paper_id = ?", (paper_id,))
        conn.execute("DELETE FROM history WHERE paper_id = ?", (paper_id,))
        conn.execute("DELETE FROM papers WHERE id = ?", (paper_id,))
    return title


def set_kind(cfg: Config, conn: sqlite3.Connection, paper_id: str, kind: str) -> None:
    if kind not in VALID_KINDS:
        raise LibraryError(f"invalid kind '{kind}' (allowed: {sorted(VALID_KINDS)})")
    row = conn.execute("SELECT 1 FROM papers WHERE id = ?", (paper_id,)).fetchone()
    if not row:
        raise LibraryError(f"no paper with id {paper_id}")
    meta = storage.read_metadata(cfg, paper_id)
    meta.kind = kind
    storage.write_metadata(cfg, meta)
    with conn:
        conn.execute("UPDATE papers SET kind = ? WHERE id = ?", (kind, paper_id))


def rename(cfg: Config, conn: sqlite3.Connection, paper_id: str, title: str) -> None:
    title = title.strip()
    if not title:
        raise LibraryError("title cannot be empty")
    meta = storage.read_metadata(cfg, paper_id)
    meta.title = title
    storage.write_metadata(cfg, meta)
    with conn:
        conn.execute("UPDATE papers SET title = ? WHERE id = ?", (title, paper_id))


def set_tags(cfg: Config, conn: sqlite3.Connection, paper_id: str, tags: list[str]) -> None:
    tags = sorted({t.strip().lower().replace(" ", "-") for t in tags if t.strip()})
    meta = storage.read_metadata(cfg, paper_id)
    meta.user_tags = tags
    storage.write_metadata(cfg, meta)
    with conn:
        conn.execute("UPDATE papers SET user_tags = ? WHERE id = ?", (json.dumps(tags), paper_id))


def all_papers(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        """
        SELECT id, title, year, authors, kind, pages, user_tags, auto, added_at
        FROM papers
        ORDER BY added_at DESC
        """
    ).fetchall()
    out: list[dict] = []
    for r in rows:
        out.append({
            "id": r["id"],
            "title": r["title"],
            "year": r["year"],
            "authors": json.loads(r["authors"]),
            "kind": r["kind"] or "paper",
            "pages": r["pages"],
            "user_tags": json.loads(r["user_tags"]),
            "auto": json.loads(r["auto"]),
            "added_at": r["added_at"],
        })
    return out
