from __future__ import annotations

from fastapi import APIRouter, Request

from .. import recs

router = APIRouter()


@router.get("/")
async def home(request: Request):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    rows = recs.home_rows(cfg, conn)
    hero = recs.hero_pick(cfg, conn)
    topics = recs.top_topics(conn, limit=12)
    paper_count = conn.execute("SELECT COUNT(*) AS n FROM papers").fetchone()["n"]
    templates = request.app.state.templates
    return templates.TemplateResponse(
        request,
        "home.html",
        {
            "rows": rows,
            "hero": hero,
            "topics": topics,
            "paper_count": paper_count,
        },
    )
