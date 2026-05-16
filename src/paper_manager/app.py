from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

import markdown as md
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from markupsafe import Markup

from . import config, db, prefs, storage


def _md_to_html(text: str) -> Markup:
    if not text:
        return Markup("")
    html = md.markdown(text, extensions=["extra", "sane_lists", "tables"])
    return Markup(html)

PACKAGE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = PACKAGE_DIR / "templates"
STATIC_DIR = PACKAGE_DIR / "static"


def create_app() -> FastAPI:
    cfg = config.load()
    storage.ensure_dirs(cfg)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        conn = db.connect(cfg.sqlite_path)
        db.init_schema(conn)
        prefs.load_from_icloud(cfg, conn)
        app.state.cfg = cfg
        app.state.db = conn
        try:
            yield
        finally:
            conn.close()

    app = FastAPI(title="Paper Manager", lifespan=lifespan)

    templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
    templates.env.globals["url_for_paper"] = lambda pid: f"/paper/{pid}"
    templates.env.filters["markdown"] = _md_to_html
    app.state.templates = templates

    if STATIC_DIR.exists():
        app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

    from .routes import home, library, manage, paper, papers, ingest, discover, settings  # noqa: E402

    app.include_router(home.router)
    app.include_router(library.router)
    app.include_router(paper.router)
    app.include_router(papers.router)
    app.include_router(manage.router)
    app.include_router(ingest.router)
    app.include_router(discover.router)
    app.include_router(settings.router)

    @app.exception_handler(404)
    async def not_found(request: Request, _):
        return HTMLResponse(
            content=f"<h1>404</h1><p>{request.url.path} doesn't exist.</p>",
            status_code=404,
        )

    return app
