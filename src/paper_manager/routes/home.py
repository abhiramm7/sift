from __future__ import annotations

from fastapi import APIRouter, Request

from .. import discover, recs

router = APIRouter()


@router.get("/")
async def home(request: Request):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    rows = recs.home_rows(cfg, conn)
    hero = recs.hero_pick(cfg, conn)
    topics = recs.top_topics(conn, limit=12)
    paper_count = conn.execute("SELECT COUNT(*) AS n FROM papers").fetchone()["n"]

    # Gather all paper_ids that appear in any rec row + the hero, fetch their
    # rating state in one query so the template can render rate widgets.
    all_ids: set[str] = set()
    if hero:
        all_ids.add(hero.paper_id)
    for r in rows:
        for p in r.papers:
            all_ids.add(p.paper_id)
    rating_state = _rating_states(conn, all_ids)
    discover_payload = discover.load(cfg)

    templates = request.app.state.templates
    return templates.TemplateResponse(
        request,
        "home.html",
        {
            "rows": rows,
            "hero": hero,
            "topics": topics,
            "paper_count": paper_count,
            "rating_state": rating_state,
            "discover": discover_payload,
        },
    )


def _rating_states(conn, ids: set[str]) -> dict[str, str]:
    if not ids:
        return {}
    placeholders = ",".join("?" * len(ids))
    rows = conn.execute(
        f"SELECT paper_id, rating FROM prefs WHERE paper_id IN ({placeholders})",
        list(ids),
    ).fetchall()
    out: dict[str, str] = {pid: "none" for pid in ids}
    for r in rows:
        if r["rating"] == 1:
            out[r["paper_id"]] = "up"
        elif r["rating"] == -1:
            out[r["paper_id"]] = "down"
    return out
