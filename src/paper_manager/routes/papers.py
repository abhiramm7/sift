from __future__ import annotations

import json
import sqlite3
from collections import defaultdict

from fastapi import APIRouter, Request

from .. import figures, storage

router = APIRouter()


@router.get("/papers")
async def papers_page(request: Request):
    cfg = request.app.state.cfg
    conn: sqlite3.Connection = request.app.state.db
    templates = request.app.state.templates
    rows = conn.execute(
        """
        SELECT id, title, authors, year, venue, doi, arxiv_id, added_at, user_tags, auto, summary
        FROM papers
        WHERE COALESCE(kind, 'paper') = 'paper'
        ORDER BY year DESC NULLS LAST, added_at DESC
        """
    ).fetchall()
    papers = [_row_to_dict(r) for r in rows]
    for p in papers:
        p["figures"] = figures.load_manifest(storage.figures_dir(cfg, p["id"]))
    by_year: dict[str, list[dict]] = defaultdict(list)
    for p in papers:
        key = str(p["year"]) if p["year"] else "Undated"
        by_year[key].append(p)
    # Year keys, undated bucket goes to the end.
    year_keys = sorted([k for k in by_year if k != "Undated"], key=lambda k: int(k), reverse=True)
    if "Undated" in by_year:
        year_keys.append("Undated")
    grouped = [(y, by_year[y]) for y in year_keys]
    return templates.TemplateResponse(
        request,
        "papers.html",
        {
            "grouped": grouped,
            "total": len(papers),
        },
    )


def _row_to_dict(row: sqlite3.Row) -> dict:
    auto = json.loads(row["auto"])
    tldr = _extract_tldr(row["summary"] or "")
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
        "auto": auto,
        "summary": row["summary"] or "",
        "tldr": tldr,
    }


def _extract_tldr(summary: str) -> str:
    if "## TL;DR" not in summary:
        return ""
    return summary.split("## TL;DR", 1)[1].split("##", 1)[0].strip()
