from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

import numpy as np

from . import embed
from .config import Config
from .db import blob_to_vector


@dataclass
class SearchHit:
    paper_id: str
    chunk_idx: int
    score: float
    snippet: str
    page_start: int | None
    page_end: int | None
    title: str
    year: int | None


def _load_chunk_matrix(conn: sqlite3.Connection) -> tuple[np.ndarray, list[sqlite3.Row]]:
    rows = conn.execute(
        """
        SELECT chunks.paper_id, chunks.idx, chunks.text, chunks.page_start, chunks.page_end,
               chunks.vector, papers.title, papers.year
        FROM chunks
        JOIN papers ON papers.id = chunks.paper_id
        ORDER BY chunks.paper_id, chunks.idx
        """
    ).fetchall()
    if not rows:
        return np.zeros((0, 1024), dtype=np.float32), []
    matrix = np.stack([blob_to_vector(r["vector"]) for r in rows])
    return matrix, rows


def _normalize(v: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(v, axis=-1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    return v / norms


def semantic_search(
    cfg: Config,
    conn: sqlite3.Connection,
    query: str,
    *,
    k: int = 8,
    year_from: int | None = None,
    year_to: int | None = None,
    tag: str | None = None,
    paper_id: str | None = None,
) -> list[SearchHit]:
    matrix, rows = _load_chunk_matrix(conn)
    if not rows:
        return []
    q_vec = embed.embed_query(query, model=cfg.embed_model)
    n_matrix = _normalize(matrix)
    n_q = _normalize(q_vec.reshape(1, -1))[0]
    scores = n_matrix @ n_q
    order = np.argsort(-scores)

    hits: list[SearchHit] = []
    seen_papers: set[str] = set()
    for i in order:
        r = rows[i]
        pid = r["paper_id"]
        year = r["year"]
        if paper_id and pid != paper_id:
            continue
        if year_from and (year is None or year < year_from):
            continue
        if year_to and (year is None or year > year_to):
            continue
        if tag:
            row = conn.execute(
                "SELECT user_tags, auto FROM papers WHERE id = ?", (pid,)
            ).fetchone()
            if row:
                tags = set(json.loads(row["user_tags"]))
                auto = json.loads(row["auto"])
                tags.update(auto.get("tags", []))
                if tag not in tags:
                    continue
        if pid in seen_papers and paper_id is None:
            # one chunk per paper for cross-paper search
            continue
        seen_papers.add(pid)
        text = r["text"]
        snippet = text[:300] + ("…" if len(text) > 300 else "")
        hits.append(
            SearchHit(
                paper_id=pid,
                chunk_idx=r["idx"],
                score=float(scores[i]),
                snippet=snippet,
                page_start=r["page_start"],
                page_end=r["page_end"],
                title=r["title"],
                year=year,
            )
        )
        if len(hits) >= k:
            break
    return hits


def keyword_search(
    conn: sqlite3.Connection,
    query: str,
    *,
    k: int = 8,
) -> list[SearchHit]:
    rows = conn.execute(
        """
        SELECT chunks_fts.text, chunks_fts.paper_id, chunks_fts.idx,
               chunks.page_start, chunks.page_end, papers.title, papers.year,
               bm25(chunks_fts) AS score
        FROM chunks_fts
        JOIN chunks ON chunks.paper_id = chunks_fts.paper_id AND chunks.idx = chunks_fts.idx
        JOIN papers ON papers.id = chunks_fts.paper_id
        WHERE chunks_fts MATCH ?
        ORDER BY score
        LIMIT ?
        """,
        (_fts_query(query), k * 4),
    ).fetchall()
    hits: list[SearchHit] = []
    seen: set[str] = set()
    for r in rows:
        if r["paper_id"] in seen:
            continue
        seen.add(r["paper_id"])
        text = r["text"]
        snippet = text[:300] + ("…" if len(text) > 300 else "")
        hits.append(
            SearchHit(
                paper_id=r["paper_id"],
                chunk_idx=r["idx"],
                score=-float(r["score"]),
                snippet=snippet,
                page_start=r["page_start"],
                page_end=r["page_end"],
                title=r["title"],
                year=r["year"],
            )
        )
        if len(hits) >= k:
            break
    return hits


def _fts_query(q: str) -> str:
    # Quote each whitespace-separated token to keep FTS5 happy on punctuation/acronyms.
    tokens = [tok for tok in q.split() if tok]
    return " ".join(f'"{tok.replace(chr(34), "")}"' for tok in tokens) or '""'


def fetch_paper(conn: sqlite3.Connection, paper_id: str) -> dict | None:
    row = conn.execute(
        "SELECT * FROM papers WHERE id = ?",
        (paper_id,),
    ).fetchone()
    if not row:
        return None
    return _paper_row_to_dict(row)


def list_papers(
    conn: sqlite3.Connection,
    *,
    tag: str | None = None,
    year: int | None = None,
    sort: str = "recent",
    limit: int = 50,
    only_unread: bool = False,
    exclude_hidden: bool = True,
) -> list[dict]:
    order = {
        "recent": "papers.added_at DESC",
        "title": "papers.title COLLATE NOCASE ASC",
        "oldest": "papers.added_at ASC",
        "year": "papers.year DESC NULLS LAST",
    }.get(sort, "papers.added_at DESC")

    sql = """
        SELECT papers.*, prefs.rating, prefs.read, prefs.hidden, prefs.saved
        FROM papers
        LEFT JOIN prefs ON prefs.paper_id = papers.id
        WHERE 1=1
    """
    args: list = []
    if year:
        sql += " AND papers.year = ?"
        args.append(year)
    if only_unread:
        sql += " AND COALESCE(prefs.read, 0) = 0"
    if exclude_hidden:
        sql += " AND COALESCE(prefs.hidden, 0) = 0"
    sql += f" ORDER BY {order} LIMIT ?"
    args.append(limit)
    rows = conn.execute(sql, args).fetchall()
    out: list[dict] = []
    for r in rows:
        d = _paper_row_to_dict(r)
        d["rating"] = r["rating"]
        d["read"] = bool(r["read"]) if r["read"] is not None else False
        d["saved"] = bool(r["saved"]) if r["saved"] is not None else False
        if tag:
            tags = set(d["user_tags"]) | set(d["auto"].get("tags", []))
            if tag not in tags:
                continue
        out.append(d)
    return out


def _paper_row_to_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "title": row["title"],
        "authors": json.loads(row["authors"]),
        "year": row["year"],
        "venue": row["venue"],
        "doi": row["doi"],
        "arxiv_id": row["arxiv_id"],
        "added_at": row["added_at"],
        "user_tags": json.loads(row["user_tags"]),
        "auto": json.loads(row["auto"]),
        "summary": row["summary"],
    }


def all_papers_summary_view(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        "SELECT id, title, year, authors, auto, summary FROM papers"
    ).fetchall()
    out: list[dict] = []
    for r in rows:
        auto = json.loads(r["auto"])
        out.append(
            {
                "paper_id": r["id"],
                "title": r["title"],
                "year": r["year"],
                "authors": json.loads(r["authors"]),
                "tags": auto.get("tags", []),
                "tldr": (r["summary"] or "").split("## TL;DR")[-1].split("##")[0].strip()[:400],
            }
        )
    return out
