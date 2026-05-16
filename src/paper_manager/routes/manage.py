from __future__ import annotations

from fastapi import APIRouter, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .. import library

router = APIRouter()


@router.get("/manage", response_class=HTMLResponse)
async def manage_page(request: Request, kind: str | None = None, q: str | None = None):
    conn = request.app.state.db
    papers = library.all_papers(conn)
    if kind:
        papers = [p for p in papers if p["kind"] == kind]
    if q:
        ql = q.lower()
        papers = [p for p in papers if ql in p["title"].lower() or any(ql in a.lower() for a in p["authors"])]
    counts = {"paper": 0, "book": 0, "report": 0}
    for p in library.all_papers(conn):
        counts[p["kind"]] = counts.get(p["kind"], 0) + 1
    templates = request.app.state.templates
    return templates.TemplateResponse(
        request,
        "manage.html",
        {"papers": papers, "counts": counts, "filter_kind": kind, "q": q},
    )


@router.post("/manage/delete/{paper_id}")
async def manage_delete(request: Request, paper_id: str):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    title = library.delete(cfg, conn, paper_id)
    return _toast(f"Deleted: {title}")


@router.post("/manage/kind/{paper_id}")
async def manage_set_kind(request: Request, paper_id: str, kind: str = Form(...)):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    try:
        library.set_kind(cfg, conn, paper_id, kind)
    except library.LibraryError as e:
        raise HTTPException(status_code=400, detail=str(e))
    row = await _row_html(request, paper_id)
    return row


@router.post("/manage/title/{paper_id}")
async def manage_rename(request: Request, paper_id: str, title: str = Form(...)):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    try:
        library.rename(cfg, conn, paper_id, title)
    except library.LibraryError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return await _row_html(request, paper_id)


@router.post("/manage/tags/{paper_id}")
async def manage_tags(request: Request, paper_id: str, tags: str = Form("")):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    library.set_tags(cfg, conn, paper_id, [t for t in tags.split(",") if t.strip()])
    return await _row_html(request, paper_id)


async def _row_html(request: Request, paper_id: str) -> HTMLResponse:
    conn = request.app.state.db
    papers = [p for p in library.all_papers(conn) if p["id"] == paper_id]
    if not papers:
        return HTMLResponse("")
    templates = request.app.state.templates
    return templates.TemplateResponse(request, "_manage_row.html", {"p": papers[0]})


def _toast(msg: str) -> HTMLResponse:
    return HTMLResponse(f'<div class="toast">{msg}</div>')
