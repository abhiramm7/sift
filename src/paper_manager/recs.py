from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import numpy as np

from . import claude, search
from .config import Config
from .db import blob_to_vector
from .storage import now_iso

CACHE_TTL = timedelta(hours=24)


@dataclass
class RecPaper:
    paper_id: str
    title: str
    year: int | None
    authors: list[str]
    tags: list[str]
    reason: str
    score: float


@dataclass
class RecRow:
    key: str
    title: str
    papers: list[RecPaper]


def home_rows(cfg: Config, conn: sqlite3.Connection) -> list[RecRow]:
    rows: list[RecRow] = []
    cont = continue_reading(conn)
    if cont:
        rows.append(RecRow(key="continue_reading", title="Continue reading", papers=cont))

    pick = claude_picks(cfg, conn)
    if pick:
        rows.append(RecRow(key="claude_picks", title="Claude's picks for you", papers=pick))

    liked = because_you_liked(conn)
    if liked:
        rows.append(RecRow(key="because_you_liked", title="Because you liked recent papers", papers=liked))

    fav = from_favorite_tags(conn)
    if fav:
        rows.append(RecRow(key="from_favorite_tags", title="From your favorite tags", papers=fav))

    rec = recently_added(conn)
    if rec:
        rows.append(RecRow(key="recently_added", title="Recently added", papers=rec))

    return rows


@dataclass
class Topic:
    tag: str
    count: int
    sample_titles: list[str]


def top_topics(conn: sqlite3.Connection, *, limit: int = 12) -> list[Topic]:
    """Top tags across the library by frequency — used for the explore-by-topic row.

    Works without any user ratings — gives a useful entry point even on day one.
    """
    rows = conn.execute("SELECT id, title, user_tags, auto FROM papers").fetchall()
    counts: dict[str, int] = {}
    samples: dict[str, list[str]] = {}
    for r in rows:
        tags = set(json.loads(r["user_tags"])) | set(json.loads(r["auto"]).get("tags", []))
        for t in tags:
            counts[t] = counts.get(t, 0) + 1
            samples.setdefault(t, [])
            if len(samples[t]) < 3:
                samples[t].append(r["title"])
    ordered = sorted(counts.items(), key=lambda kv: -kv[1])[:limit]
    return [Topic(tag=t, count=c, sample_titles=samples.get(t, [])) for t, c in ordered]


def hero_pick(cfg: Config, conn: sqlite3.Connection) -> RecPaper | None:
    """One paper to feature at the top of the home page.

    Preference order: a Claude pick → similar to most recently liked → most recently added.
    """
    picks = claude_picks(cfg, conn, n=1)
    if picks:
        return picks[0]
    liked = because_you_liked(conn, limit=1)
    if liked:
        return liked[0]
    recent = recently_added(conn, limit=1)
    if recent:
        return recent[0]
    return None


def continue_reading(conn: sqlite3.Connection, *, limit: int = 8) -> list[RecPaper]:
    rows = conn.execute(
        """
        SELECT papers.id, papers.title, papers.year, papers.authors, papers.auto, papers.user_tags, MAX(history.ts) AS last_ts
        FROM history
        JOIN papers ON papers.id = history.paper_id
        LEFT JOIN prefs ON prefs.paper_id = papers.id
        WHERE history.event = 'opened'
          AND COALESCE(prefs.read, 0) = 0
          AND COALESCE(prefs.hidden, 0) = 0
        GROUP BY papers.id
        ORDER BY last_ts DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    return [_row_to_rec(r, reason="Picked up recently") for r in rows]


def recently_added(conn: sqlite3.Connection, *, limit: int = 12) -> list[RecPaper]:
    rows = conn.execute(
        """
        SELECT papers.id, papers.title, papers.year, papers.authors, papers.auto, papers.user_tags
        FROM papers
        LEFT JOIN prefs ON prefs.paper_id = papers.id
        WHERE COALESCE(prefs.hidden, 0) = 0
        ORDER BY papers.added_at DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    return [_row_to_rec(r, reason="New in your library") for r in rows]


def because_you_liked(conn: sqlite3.Connection, *, limit: int = 8) -> list[RecPaper]:
    liked = conn.execute(
        """
        SELECT papers.id, papers.title, papers.summary_vec
        FROM prefs
        JOIN papers ON papers.id = prefs.paper_id
        WHERE prefs.rating >= 1
        ORDER BY prefs.updated_at DESC
        LIMIT 1
        """
    ).fetchone()
    if not liked or not liked["summary_vec"]:
        return []

    seed_vec = blob_to_vector(liked["summary_vec"])
    candidates = conn.execute(
        """
        SELECT papers.id, papers.title, papers.year, papers.authors, papers.auto, papers.user_tags, papers.summary_vec
        FROM papers
        LEFT JOIN prefs ON prefs.paper_id = papers.id
        WHERE papers.id != ?
          AND COALESCE(prefs.read, 0) = 0
          AND COALESCE(prefs.hidden, 0) = 0
          AND COALESCE(prefs.rating, 0) >= 0
        """,
        (liked["id"],),
    ).fetchall()
    if not candidates:
        return []

    matrix = np.stack([blob_to_vector(r["summary_vec"]) for r in candidates])
    scores = _cosine_against(seed_vec, matrix)
    order = np.argsort(-scores)[:limit]
    out: list[RecPaper] = []
    for i in order:
        r = candidates[int(i)]
        out.append(_row_to_rec(r, reason=f"Similar to '{liked['title']}'", score=float(scores[int(i)])))
    return out


def from_favorite_tags(conn: sqlite3.Connection, *, limit: int = 8) -> list[RecPaper]:
    tag_counts: dict[str, int] = {}
    rows = conn.execute(
        """
        SELECT papers.user_tags, papers.auto
        FROM prefs
        JOIN papers ON papers.id = prefs.paper_id
        WHERE prefs.rating >= 1
        """
    ).fetchall()
    for r in rows:
        tags = set(json.loads(r["user_tags"])) | set(json.loads(r["auto"]).get("tags", []))
        for t in tags:
            tag_counts[t] = tag_counts.get(t, 0) + 1
    if not tag_counts:
        return []
    top = sorted(tag_counts.items(), key=lambda kv: -kv[1])[:3]

    out: list[RecPaper] = []
    seen: set[str] = set()
    for tag, _ in top:
        if len(out) >= limit:
            break
        papers = search.list_papers(conn, tag=tag, limit=10, only_unread=True)
        for p in papers:
            if p["id"] in seen:
                continue
            seen.add(p["id"])
            out.append(_paper_dict_to_rec(p, reason=f"In your favorite tag: {tag}"))
            if len(out) >= limit:
                break
    return out


def claude_picks(cfg: Config, conn: sqlite3.Connection, *, n: int = 5) -> list[RecPaper]:
    cached = _read_cache(conn, "claude_picks")
    if cached is not None:
        return cached

    liked = conn.execute(
        """
        SELECT papers.id, papers.title, papers.year, papers.summary
        FROM prefs
        JOIN papers ON papers.id = prefs.paper_id
        WHERE prefs.rating >= 1
        ORDER BY prefs.updated_at DESC
        LIMIT 10
        """
    ).fetchall()
    if not liked:
        return []

    liked_payload = [
        {
            "paper_id": r["id"],
            "title": r["title"],
            "year": r["year"],
            "tldr": _tldr(r["summary"]),
        }
        for r in liked
    ]

    cand_rows = conn.execute(
        """
        SELECT papers.id, papers.title, papers.year, papers.authors, papers.summary, papers.auto, papers.user_tags
        FROM papers
        LEFT JOIN prefs ON prefs.paper_id = papers.id
        WHERE COALESCE(prefs.read, 0) = 0
          AND COALESCE(prefs.hidden, 0) = 0
          AND COALESCE(prefs.rating, 0) = 0
        ORDER BY papers.added_at DESC
        LIMIT 60
        """
    ).fetchall()
    if not cand_rows:
        return []

    candidates_payload = [
        {
            "paper_id": r["id"],
            "title": r["title"],
            "year": r["year"],
            "tldr": _tldr(r["summary"]),
        }
        for r in cand_rows
    ]

    try:
        picks = claude.recommend(liked_payload, candidates_payload, model=cfg.claude_model, n=n)
    except Exception:
        picks = []

    by_id = {r["id"]: r for r in cand_rows}
    out: list[RecPaper] = []
    for pick in picks:
        pid = pick.get("paper_id")
        reason = pick.get("reason", "")
        row = by_id.get(pid)
        if row:
            out.append(_row_to_rec(row, reason=reason))
    _write_cache(conn, "claude_picks", out)
    return out


def _row_to_rec(r: sqlite3.Row, reason: str, score: float = 0.0) -> RecPaper:
    return RecPaper(
        paper_id=r["id"],
        title=r["title"],
        year=r["year"],
        authors=json.loads(r["authors"]) if isinstance(r["authors"], (str, bytes)) else r["authors"],
        tags=sorted(set(json.loads(r["user_tags"])) | set(json.loads(r["auto"]).get("tags", []))),
        reason=reason,
        score=score,
    )


def _paper_dict_to_rec(p: dict, reason: str) -> RecPaper:
    return RecPaper(
        paper_id=p["id"],
        title=p["title"],
        year=p["year"],
        authors=p["authors"],
        tags=sorted(set(p["user_tags"]) | set(p["auto"].get("tags", []))),
        reason=reason,
        score=0.0,
    )


def _cosine_against(seed: np.ndarray, matrix: np.ndarray) -> np.ndarray:
    s = seed / (np.linalg.norm(seed) or 1.0)
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    return (matrix / norms) @ s


def _tldr(summary: str) -> str:
    return (summary or "").split("## TL;DR")[-1].split("##")[0].strip()[:400]


def _read_cache(conn: sqlite3.Connection, key: str) -> list[RecPaper] | None:
    row = conn.execute(
        "SELECT payload, refreshed_at FROM recs_cache WHERE row_key = ?",
        (key,),
    ).fetchone()
    if not row:
        return None
    refreshed = datetime.fromisoformat(row["refreshed_at"])
    if datetime.now(timezone.utc) - refreshed > CACHE_TTL:
        return None
    data = json.loads(row["payload"])
    return [RecPaper(**d) for d in data]


def _write_cache(conn: sqlite3.Connection, key: str, items: list[RecPaper]) -> None:
    payload = json.dumps([item.__dict__ for item in items])
    conn.execute(
        """
        INSERT INTO recs_cache(row_key, payload, refreshed_at)
        VALUES(?, ?, ?)
        ON CONFLICT(row_key) DO UPDATE SET
            payload = excluded.payload,
            refreshed_at = excluded.refreshed_at
        """,
        (key, payload, now_iso()),
    )
    conn.commit()
