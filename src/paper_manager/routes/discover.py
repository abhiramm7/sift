from __future__ import annotations

import tempfile
from pathlib import Path

import httpx
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from .. import discover as discover_svc
from .. import ingest as ingest_svc

router = APIRouter()


@router.post("/discover/ingest/{arxiv_id}")
async def ingest_arxiv_candidate(request: Request, arxiv_id: str):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    payload = discover_svc.load(cfg)
    cand = next(
        (c for c in payload.get("candidates", []) if c.get("arxiv_id") == arxiv_id),
        None,
    )
    if not cand:
        return HTMLResponse("")

    pdf_url = cand.get("pdf_url") or f"https://arxiv.org/pdf/{arxiv_id}.pdf"
    try:
        with httpx.Client(follow_redirects=True, timeout=60.0, headers={"User-Agent": "paper_manager/0.1"}) as client:
            r = client.get(pdf_url)
            r.raise_for_status()
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tf:
            tf.write(r.content)
            tmp_path = Path(tf.name)
        try:
            result = ingest_svc.ingest_pdf(cfg, conn, tmp_path, source=f"arxiv:{arxiv_id}")
        finally:
            tmp_path.unlink(missing_ok=True)
    except Exception as e:
        return HTMLResponse(f'<div class="toast toast-error">ingest failed: {e}</div>')

    discover_svc.dismiss(cfg, arxiv_id)
    return HTMLResponse(
        f'<div class="discover-done">✓ added <a href="/paper/{result.paper_id}">{result.title}</a></div>'
    )


@router.post("/discover/dismiss/{arxiv_id}")
async def dismiss(request: Request, arxiv_id: str):
    cfg = request.app.state.cfg
    discover_svc.dismiss(cfg, arxiv_id)
    return HTMLResponse("")
