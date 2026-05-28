from __future__ import annotations

import html
import tempfile
from pathlib import Path

from fastapi import APIRouter, File, Form, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse

from .. import fetch_url, ingest as ingest_svc

router = APIRouter()


@router.post("/papers")
async def upload_pdf(
    request: Request,
    pdfs: list[UploadFile] = File(...),
    tags: str = Form(""),
):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    tag_list = [t.strip() for t in tags.split(",") if t.strip()]
    results: list[dict] = []
    for upload in pdfs:
        if not upload.filename or not upload.filename.lower().endswith(".pdf"):
            continue
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tf:
            tf.write(await upload.read())
            tmp_path = Path(tf.name)
        try:
            result = ingest_svc.ingest_pdf(cfg, conn, tmp_path, user_tags=tag_list)
            results.append(
                {
                    "title": result.title,
                    "paper_id": result.paper_id,
                    "new": result.new,
                }
            )
        finally:
            tmp_path.unlink(missing_ok=True)

    body = "<ul>" + "".join(
        f'<li><a href="/paper/{r["paper_id"]}">{r["title"]}</a> ({"new" if r["new"] else "duplicate"})</li>'
        for r in results
    ) + "</ul>"
    return HTMLResponse(f"<div class=\"toast\">Ingested {len(results)} paper(s):{body}</div>")


@router.post("/papers/by-url")
async def upload_url(
    request: Request,
    url: str = Form(...),
    tags: str = Form(""),
):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    tag_list = [t.strip() for t in tags.split(",") if t.strip()]
    url = url.strip()
    if not url:
        return HTMLResponse('<div class="toast">URL is required.</div>')

    try:
        fetched = fetch_url.fetch(url)
    except Exception as e:
        return HTMLResponse(
            f'<div class="toast">Fetch failed for <code>{html.escape(url)}</code>: '
            f'<em>{html.escape(str(e))}</em></div>'
        )

    try:
        if fetched.pdf_path:
            result = ingest_svc.ingest_pdf(
                cfg, conn, fetched.pdf_path,
                user_tags=tag_list,
                source=f"{fetched.source_kind}:{fetched.source_url}",
            )
            fetched.pdf_path.unlink(missing_ok=True)
        else:
            result = ingest_svc.ingest_text(
                cfg, conn,
                text=fetched.text,
                title_hint=fetched.title_hint,
                source_url=fetched.source_url,
                source_kind=fetched.source_kind,
                user_tags=tag_list,
            )
    except Exception as e:
        return HTMLResponse(
            f'<div class="toast">Ingest failed: <em>{html.escape(str(e))}</em></div>'
        )

    state = "added" if result.new else "already in library"
    return HTMLResponse(
        f'<div class="toast">{state}: '
        f'<a href="/paper/{result.paper_id}">{html.escape(result.title)}</a></div>'
    )


@router.post("/ingest/inbox")
async def scan_inbox(request: Request):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    pdfs = sorted(cfg.inbox_dir.glob("*.pdf"))
    results: list[dict] = []
    for p in pdfs:
        try:
            result = ingest_svc.ingest_pdf(cfg, conn, p)
            results.append({"title": result.title, "paper_id": result.paper_id, "new": result.new})
            if result.new:
                p.unlink(missing_ok=True)
        except Exception as e:
            results.append({"title": p.name, "error": str(e)})

    if not results:
        return HTMLResponse('<div class="toast">Inbox is empty.</div>')

    items: list[str] = []
    for r in results:
        if "error" in r:
            items.append(f'<li>{r["title"]}: <em>{r["error"]}</em></li>')
        else:
            items.append(
                f'<li><a href="/paper/{r["paper_id"]}">{r["title"]}</a>'
                f' ({"new" if r["new"] else "duplicate"})</li>'
            )
    return HTMLResponse(f'<div class="toast">Scanned inbox:<ul>{"".join(items)}</ul></div>')
