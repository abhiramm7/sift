"""Bake the /papers page (and per-paper detail pages) into a static directory
suitable for `git push` to a GitHub Pages repo."""
from __future__ import annotations

import json
import re
import shutil
import sqlite3
from collections import defaultdict
from pathlib import Path

import markdown as md
from jinja2 import Environment, FileSystemLoader, select_autoescape
from markupsafe import Markup

from . import figures, storage
from .config import Config


def _md_to_html(text: str) -> Markup:
    if not text:
        return Markup("")
    return Markup(md.markdown(text, extensions=["extra", "sane_lists", "tables"]))

PACKAGE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = PACKAGE_DIR / "templates"
STATIC_DIR = PACKAGE_DIR / "static"


def export(cfg: Config, conn: sqlite3.Connection, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "static").mkdir(exist_ok=True)
    (out_dir / "paper").mkdir(exist_ok=True)

    if STATIC_DIR.exists():
        for f in STATIC_DIR.iterdir():
            if f.is_file():
                shutil.copy2(f, out_dir / "static" / f.name)

    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        autoescape=select_autoescape(["html"]),
    )
    env.globals["url_for_paper"] = _static_paper_url
    env.globals["STATIC_MODE"] = True
    env.filters["markdown"] = _md_to_html

    papers = _load_papers(conn)
    for p in papers:
        p["figures"] = _copy_figures(cfg, p["id"], out_dir)

    grouped = _group_by_year(papers)
    hero = papers[0] if papers else None
    recent = papers[:8]
    topics = _top_topics(papers, limit=12)

    _render_index(env, out_dir, grouped, total=len(papers), hero=hero, recent=recent, topics=topics)
    for p in papers:
        _render_paper(env, out_dir, p)

    return {"papers": len(papers), "out_dir": str(out_dir)}


def _copy_figures(cfg: Config, paper_id: str, out_dir: Path) -> list[dict]:
    src_dir = storage.figures_dir(cfg, paper_id)
    manifest = figures.load_manifest(src_dir)
    if not manifest:
        return []
    dest = out_dir / "figures" / paper_id
    dest.mkdir(parents=True, exist_ok=True)
    for entry in manifest:
        fname = entry["filename"]
        src = src_dir / fname
        if src.exists():
            shutil.copy2(src, dest / fname)
    return manifest


def _load_papers(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        """
        SELECT id, title, authors, year, venue, doi, arxiv_id, added_at,
               user_tags, auto, summary
        FROM papers
        WHERE COALESCE(kind, 'paper') = 'paper'
        ORDER BY year DESC NULLS LAST, added_at DESC
        """
    ).fetchall()
    out: list[dict] = []
    for r in rows:
        auto = json.loads(r["auto"])
        summary = r["summary"] or ""
        out.append(
            {
                "id": r["id"],
                "title": r["title"],
                "authors": json.loads(r["authors"]),
                "year": r["year"],
                "venue": r["venue"],
                "doi": r["doi"],
                "arxiv_id": r["arxiv_id"],
                "added_at": r["added_at"],
                "user_tags": json.loads(r["user_tags"]),
                "auto": auto,
                "summary": summary,
                "tldr": _extract_tldr(summary),
            }
        )
    return out


def _group_by_year(papers: list[dict]) -> list[tuple[str, list[dict]]]:
    by_year: dict[str, list[dict]] = defaultdict(list)
    for p in papers:
        key = str(p["year"]) if p["year"] else "Undated"
        by_year[key].append(p)
    years = sorted([k for k in by_year if k != "Undated"], key=lambda k: int(k), reverse=True)
    if "Undated" in by_year:
        years.append("Undated")
    return [(y, by_year[y]) for y in years]


def _render_index(env, out_dir: Path, grouped, total: int, hero, recent, topics) -> None:
    tpl = env.get_template("static_index.html")
    html = tpl.render(
        grouped=grouped, total=total,
        hero=hero, recent=recent, topics=topics,
    )
    (out_dir / "index.html").write_text(html, encoding="utf-8")


def _top_topics(papers: list[dict], limit: int) -> list[dict]:
    counts: dict[str, int] = {}
    for p in papers:
        tags = set(p.get("user_tags", [])) | set((p.get("auto") or {}).get("tags", []))
        for t in tags:
            counts[t] = counts.get(t, 0) + 1
    ordered = sorted(counts.items(), key=lambda kv: -kv[1])[:limit]
    return [{"tag": t, "count": c} for t, c in ordered]


def _render_paper(env, out_dir: Path, paper: dict) -> None:
    tpl = env.get_template("static_paper.html")
    html = tpl.render(paper=paper)
    (out_dir / "paper" / f"{paper['id']}.html").write_text(html, encoding="utf-8")


def _static_paper_url(paper_id: str) -> str:
    return f"./paper/{paper_id}.html"


def _extract_tldr(summary: str) -> str:
    if "## TL;DR" not in summary:
        return ""
    return summary.split("## TL;DR", 1)[1].split("##", 1)[0].strip()


def slugify(value: str) -> str:
    return re.sub(r"[^a-z0-9-]+", "-", value.lower()).strip("-")
