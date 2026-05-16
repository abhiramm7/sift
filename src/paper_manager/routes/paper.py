from __future__ import annotations

from fastapi import APIRouter, Form, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse

from .. import figures, prefs, search, storage

router = APIRouter()


@router.get("/paper/{paper_id}")
async def paper_page(request: Request, paper_id: str):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    paper = search.fetch_paper(conn, paper_id)
    if not paper:
        raise HTTPException(status_code=404, detail="paper not found")
    user_prefs = prefs.get_prefs(conn, paper_id)
    prefs.log_event(cfg, conn, paper_id, "opened")
    fig_manifest = figures.load_manifest(storage.figures_dir(cfg, paper_id))
    templates = request.app.state.templates
    return templates.TemplateResponse(
        request,
        "paper.html",
        {
            "paper": paper,
            "prefs": user_prefs,
            "figures": fig_manifest,
        },
    )


@router.get("/paper/{paper_id}/figure/{filename}")
async def paper_figure(request: Request, paper_id: str, filename: str):
    cfg = request.app.state.cfg
    path = storage.figures_dir(cfg, paper_id) / filename
    if not path.exists() or ".." in filename or "/" in filename:
        raise HTTPException(status_code=404, detail="figure not found")
    media = "image/png" if filename.lower().endswith(".png") else "image/jpeg"
    return FileResponse(path, media_type=media)


@router.get("/paper/{paper_id}/pdf")
async def paper_pdf(request: Request, paper_id: str):
    cfg = request.app.state.cfg
    path = storage.pdf_path(cfg, paper_id)
    if not path.exists():
        raise HTTPException(status_code=404, detail="pdf missing")
    return FileResponse(path, media_type="application/pdf", filename=f"{paper_id}.pdf")


@router.post("/paper/{paper_id}/rate")
async def rate(request: Request, paper_id: str, rating: int | None = Form(default=None)):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    prefs.set_rating(cfg, conn, paper_id, rating)
    user_prefs = prefs.get_prefs(conn, paper_id)
    return HTMLResponse(_rating_widget(paper_id, user_prefs))


@router.post("/quick-rate/{paper_id}")
async def quick_rate(request: Request, paper_id: str, rating: int = Form(...)):
    """Compact rate endpoint used by card tiles on /home. 0 clears, 1 = like, -1 = skip."""
    cfg = request.app.state.cfg
    conn = request.app.state.db
    new_rating: int | None = rating if rating in (1, -1) else None
    prefs.set_rating(cfg, conn, paper_id, new_rating)
    state = _state_for(new_rating)
    templates = request.app.state.templates
    return templates.TemplateResponse(
        request, "_card_rate.html", {"paper_id": paper_id, "state": state}
    )


def _state_for(rating: int | None) -> str:
    if rating == 1:
        return "up"
    if rating == -1:
        return "down"
    return "none"


@router.post("/paper/{paper_id}/flag")
async def flag(
    request: Request,
    paper_id: str,
    saved: int | None = Form(default=None),
    hidden: int | None = Form(default=None),
    read: int | None = Form(default=None),
):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    prefs.set_flag(
        cfg,
        conn,
        paper_id,
        saved=bool(saved) if saved is not None else None,
        hidden=bool(hidden) if hidden is not None else None,
        read=bool(read) if read is not None else None,
    )
    user_prefs = prefs.get_prefs(conn, paper_id)
    return HTMLResponse(_flag_widget(paper_id, user_prefs))


def _rating_widget(paper_id: str, p: dict) -> str:
    up = "★" if p["rating"] == 1 else "☆"
    down = "▼" if p["rating"] == -1 else "▽"
    clear = "·" if p["rating"] is None else "✕"
    return f"""
    <div class="rating" id="rating-{paper_id}">
      <button hx-post="/paper/{paper_id}/rate" hx-vals='{{"rating": 1}}' hx-target="#rating-{paper_id}" hx-swap="outerHTML">{up} like</button>
      <button hx-post="/paper/{paper_id}/rate" hx-vals='{{"rating": -1}}' hx-target="#rating-{paper_id}" hx-swap="outerHTML">{down} skip</button>
      <button hx-post="/paper/{paper_id}/rate" hx-target="#rating-{paper_id}" hx-swap="outerHTML">{clear} clear</button>
    </div>
    """


def _flag_widget(paper_id: str, p: dict) -> str:
    saved_label = "★ saved" if p["saved"] else "☆ save"
    read_label = "✓ read" if p["read"] else "○ mark read"
    hidden_label = "● hidden" if p["hidden"] else "○ hide"
    return f"""
    <div class="flags" id="flags-{paper_id}">
      <button hx-post="/paper/{paper_id}/flag" hx-vals='{{"saved": {0 if p["saved"] else 1}}}' hx-target="#flags-{paper_id}" hx-swap="outerHTML">{saved_label}</button>
      <button hx-post="/paper/{paper_id}/flag" hx-vals='{{"read": {0 if p["read"] else 1}}}' hx-target="#flags-{paper_id}" hx-swap="outerHTML">{read_label}</button>
      <button hx-post="/paper/{paper_id}/flag" hx-vals='{{"hidden": {0 if p["hidden"] else 1}}}' hx-target="#flags-{paper_id}" hx-swap="outerHTML">{hidden_label}</button>
    </div>
    """


def rating_widget_html(paper_id: str, p: dict) -> str:
    return _rating_widget(paper_id, p)


def flag_widget_html(paper_id: str, p: dict) -> str:
    return _flag_widget(paper_id, p)
