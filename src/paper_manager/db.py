from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

import numpy as np

SCHEMA = """
CREATE TABLE IF NOT EXISTS papers (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    authors      TEXT NOT NULL,           -- JSON array
    year         INTEGER,
    venue        TEXT,
    doi          TEXT,
    arxiv_id     TEXT,
    added_at     TEXT NOT NULL,
    sha256       TEXT NOT NULL,
    source       TEXT NOT NULL,
    kind         TEXT NOT NULL DEFAULT 'paper',  -- 'paper' | 'book' | 'report'
    pages        INTEGER,
    user_tags    TEXT NOT NULL DEFAULT '[]',
    auto         TEXT NOT NULL DEFAULT '{}',
    summary      TEXT NOT NULL DEFAULT '',
    summary_vec  BLOB
);

CREATE TABLE IF NOT EXISTS chunks (
    paper_id     TEXT NOT NULL,
    idx          INTEGER NOT NULL,
    text         TEXT NOT NULL,
    page_start   INTEGER,
    page_end     INTEGER,
    vector       BLOB NOT NULL,
    PRIMARY KEY (paper_id, idx),
    FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chunks_paper ON chunks(paper_id);

CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    text,
    paper_id UNINDEXED,
    idx UNINDEXED
);

CREATE TABLE IF NOT EXISTS prefs (
    paper_id     TEXT PRIMARY KEY,
    rating       INTEGER,                  -- -1 thumbs-down, 1 thumbs-up, 2..5 stars
    saved        INTEGER NOT NULL DEFAULT 0,
    hidden       INTEGER NOT NULL DEFAULT 0,
    read         INTEGER NOT NULL DEFAULT 0,
    updated_at   TEXT NOT NULL,
    FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS followed_tags (
    tag          TEXT PRIMARY KEY,
    added_at     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS history (
    rowid        INTEGER PRIMARY KEY AUTOINCREMENT,
    paper_id     TEXT NOT NULL,
    event        TEXT NOT NULL,            -- opened|dwelled|chat
    ts           TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_history_paper ON history(paper_id);
CREATE INDEX IF NOT EXISTS idx_history_ts ON history(ts);

CREATE TABLE IF NOT EXISTS recs_cache (
    row_key      TEXT PRIMARY KEY,         -- e.g. "claude_picks", "because_you_liked"
    payload      TEXT NOT NULL,            -- JSON
    refreshed_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS state (
    key          TEXT PRIMARY KEY,
    value        TEXT NOT NULL
);
"""


def vector_to_blob(v: np.ndarray) -> bytes:
    return np.asarray(v, dtype=np.float32).tobytes()


def blob_to_vector(b: bytes) -> np.ndarray:
    return np.frombuffer(b, dtype=np.float32)


def connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    _migrate(conn)
    conn.commit()


def _migrate(conn: sqlite3.Connection) -> None:
    """Add columns that may be missing on older DBs. Idempotent."""
    cols = {r[1] for r in conn.execute("PRAGMA table_info(papers)").fetchall()}
    if "kind" not in cols:
        conn.execute("ALTER TABLE papers ADD COLUMN kind TEXT NOT NULL DEFAULT 'paper'")
    if "pages" not in cols:
        conn.execute("ALTER TABLE papers ADD COLUMN pages INTEGER")


@contextmanager
def transaction(conn: sqlite3.Connection) -> Iterator[sqlite3.Connection]:
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise


def get_state(conn: sqlite3.Connection, key: str) -> str | None:
    row = conn.execute("SELECT value FROM state WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else None


def set_state(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute(
        "INSERT INTO state(key, value) VALUES(?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        (key, value),
    )
    conn.commit()
