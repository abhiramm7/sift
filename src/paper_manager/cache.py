from __future__ import annotations

import json
import sqlite3

import numpy as np

from . import embed, pdf, storage
from .config import Config
from .db import transaction, vector_to_blob


def rebuild(cfg: Config, conn: sqlite3.Connection) -> dict:
    """Rebuild SQLite tables from the iCloud library files.

    Re-chunks each paper from cached text (so chunk size matches the current
    embedder's context window) and re-embeds with the configured embedder.
    Cheap when running locally — no rate limits, no API costs.
    """
    paper_ids = storage.list_paper_ids(cfg)
    refreshed = 0
    chunk_total = 0

    with transaction(conn):
        conn.execute("DELETE FROM chunks")
        conn.execute("DELETE FROM chunks_fts")
        conn.execute("DELETE FROM papers")

    errors: list[str] = []
    for pid in paper_ids:
        try:
            meta = storage.read_metadata(cfg, pid)
            summary = storage.read_summary(cfg, pid) if storage.summary_path(cfg, pid).exists() else ""
            text = storage.read_text(cfg, pid) if storage.text_path(cfg, pid).exists() else ""
        except Exception as e:
            errors.append(f"{pid}: read failed — {e}")
            continue

        try:
            if text.strip():
                extracted = pdf.ExtractedPdf(
                    full_text=text,
                    pages=[pdf.PageText(page=1, text=text)],
                    page_count=1,
                )
                chunks = [c for c in pdf.chunk(extracted) if c.get("text", "").strip()]
                for i, c in enumerate(chunks):
                    c["idx"] = i
                storage.write_chunks(cfg, pid, chunks)
            elif storage.chunks_path(cfg, pid).exists():
                chunks = [c for c in storage.read_chunks(cfg, pid) if c.get("text", "").strip()]
            else:
                chunks = []

            chunk_vectors = (
                embed.embed_documents([c["text"] for c in chunks], model=cfg.embed_model)
                if chunks
                else np.zeros((0, 1024), dtype=np.float32)
            )
            summary_vec = (
                embed.embed_documents([summary], model=cfg.embed_model)[0]
                if summary
                else np.zeros((1024,), dtype=np.float32)
            )

            with transaction(conn):
                conn.execute(
                    """
                    INSERT INTO papers(
                        id, title, authors, year, venue, doi, arxiv_id,
                        added_at, sha256, source, kind, pages, user_tags, auto, summary, summary_vec
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        meta.id, meta.title, json.dumps(meta.authors), meta.year,
                        meta.venue, meta.doi, meta.arxiv_id, meta.added_at,
                        meta.sha256, meta.source, meta.kind, meta.pages,
                        json.dumps(meta.user_tags), json.dumps(meta.auto),
                        summary, vector_to_blob(summary_vec),
                    ),
                )
                for c, v in zip(chunks, chunk_vectors):
                    conn.execute(
                        "INSERT INTO chunks(paper_id, idx, text, page_start, page_end, vector) "
                        "VALUES (?, ?, ?, ?, ?, ?)",
                        (meta.id, c["idx"], c["text"], c.get("page_start"), c.get("page_end"), vector_to_blob(v)),
                    )
                    conn.execute(
                        "INSERT INTO chunks_fts(text, paper_id, idx) VALUES (?, ?, ?)",
                        (c["text"], meta.id, c["idx"]),
                    )
            refreshed += 1
            chunk_total += len(chunks)
        except Exception as e:
            errors.append(f"{pid} ({meta.title if 'meta' in dir() else '?'}): {e}")
            continue

    return {"papers": refreshed, "chunks": chunk_total, "errors": errors}
