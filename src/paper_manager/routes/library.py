from __future__ import annotations

import json

from fastapi import APIRouter, Request

from .. import search

router = APIRouter()


@router.get("/library")
async def library(
    request: Request,
    tag: str | None = None,
    year: int | None = None,
    sort: str = "recent",
    q: str | None = None,
):
    cfg = request.app.state.cfg
    conn = request.app.state.db

    if q:
        hits = search.semantic_search(cfg, conn, q, k=30)
        papers = [search.fetch_paper(conn, h.paper_id) for h in hits]
        papers = [p for p in papers if p]
    else:
        papers = search.list_papers(conn, tag=tag, year=year, sort=sort, limit=200)

    all_tags = _all_tags(conn)
    all_years = _all_years(conn)
    templates = request.app.state.templates
    return templates.TemplateResponse(
        request,
        "library.html",
        {
            "papers": papers,
            "tag": tag,
            "year": year,
            "sort": sort,
            "q": q,
            "all_tags": all_tags,
            "all_years": all_years,
        },
    )


def _all_tags(conn) -> list[str]:
    rows = conn.execute("SELECT user_tags, auto FROM papers").fetchall()
    tags: set[str] = set()
    for r in rows:
        tags.update(json.loads(r["user_tags"]))
        tags.update(json.loads(r["auto"]).get("tags", []))
    return sorted(tags)


def _all_years(conn) -> list[int]:
    rows = conn.execute("SELECT DISTINCT year FROM papers WHERE year IS NOT NULL ORDER BY year DESC").fetchall()
    return [r["year"] for r in rows]
