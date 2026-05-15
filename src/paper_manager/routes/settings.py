from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from .. import cache, config

router = APIRouter()


@router.get("/settings")
async def settings_page(request: Request):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    paper_count = conn.execute("SELECT COUNT(*) AS n FROM papers").fetchone()["n"]
    chunk_count = conn.execute("SELECT COUNT(*) AS n FROM chunks").fetchone()["n"]
    templates = request.app.state.templates
    return templates.TemplateResponse(
        request,
        "settings.html",
        {
            "icloud_root": cfg.icloud_root,
            "sqlite_path": cfg.sqlite_path,
            "paper_count": paper_count,
            "chunk_count": chunk_count,
            "claude_model": cfg.claude_model,
            "embed_model": cfg.embed_model,
            "ollama_status": _ollama_status(cfg),
        },
    )


def _ollama_status(cfg) -> str:
    import httpx
    try:
        r = httpx.get("http://localhost:11434/api/tags", timeout=2.0)
        r.raise_for_status()
        models = [m.get("name", "") for m in r.json().get("models", [])]
        if any(cfg.embed_model in m for m in models):
            return "running"
        return f"running (but {cfg.embed_model} not pulled)"
    except Exception:
        return "not running"


@router.post("/settings/rebuild-cache")
async def rebuild_cache_route(request: Request):
    cfg = request.app.state.cfg
    conn = request.app.state.db
    result = cache.rebuild(cfg, conn)
    return HTMLResponse(
        f'<div class="toast">Rebuilt cache: {result["papers"]} papers, {result["chunks"]} chunks.</div>'
    )
