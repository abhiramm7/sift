from __future__ import annotations

from pathlib import Path

import typer
from rich.console import Console
from rich.table import Table

from . import cache, config, db, ingest, library, storage

app = typer.Typer(help="Paper Manager — a local web app for your paper library.")
console = Console()


def _claude_on_path() -> bool:
    import shutil
    return shutil.which("claude") is not None


def _check_ollama() -> str:
    import httpx
    try:
        r = httpx.get("http://localhost:11434/api/tags", timeout=2.0)
        r.raise_for_status()
        models = [m.get("name", "") for m in r.json().get("models", [])]
        cfg = config.load()
        if any(cfg.embed_model in m for m in models):
            return f"running, [bold]{cfg.embed_model}[/bold] available"
        return f"running, but {cfg.embed_model} not pulled — `ollama pull {cfg.embed_model}`"
    except Exception:
        return "[red]not running — `brew services start ollama`[/red]"


@app.command()
def init(
    config_path: Path = typer.Option(
        Path.cwd() / "config.toml", "--config", help="Where to write config.toml."
    ),
    icloud_root: Path | None = typer.Option(
        None, "--icloud-root", help="Override the iCloud PaperManager root."
    ),
) -> None:
    """Create iCloud folders, init the SQLite cache, and write config.toml."""
    written = config.write_default(path=config_path, icloud_root=icloud_root)
    cfg = config.load(written)
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    conn.close()
    console.print(f"[green]✓[/green] config:  {written}")
    console.print(f"[green]✓[/green] iCloud:  {cfg.icloud_root}")
    console.print(f"[green]✓[/green] sqlite:  {cfg.sqlite_path}")
    console.print()
    console.print("Make sure [bold]ollama[/bold] is running and [bold]mxbai-embed-large[/bold] is pulled, then run [bold]paper add <pdf>[/bold] or [bold]paper serve[/bold].")


@app.command()
def add(
    pdf: Path = typer.Argument(..., exists=True, dir_okay=False, readable=True),
    tags: str = typer.Option("", "--tags", help="Comma-separated user tags."),
) -> None:
    """Ingest a PDF into the library."""
    cfg = config.load()
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    tag_list = [t.strip() for t in tags.split(",") if t.strip()]
    result = ingest.ingest_pdf(cfg, conn, pdf, user_tags=tag_list)
    conn.close()
    state = "added" if result.new else "already in library"
    console.print(f"[green]✓[/green] {state}: [bold]{result.title}[/bold]  ({result.paper_id}, {result.chunk_count} chunks)")


@app.command()
def status() -> None:
    """Show library counts, paths, and API key availability."""
    cfg = config.load()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    paper_count = conn.execute("SELECT COUNT(*) AS n FROM papers").fetchone()["n"]
    chunk_count = conn.execute("SELECT COUNT(*) AS n FROM chunks").fetchone()["n"]
    conn.close()

    icloud_exists = cfg.icloud_root.exists()
    inbox_exists = cfg.inbox_dir.exists()
    library_exists = cfg.library_dir.exists()

    table = Table(show_header=False, box=None)
    table.add_row("iCloud root", str(cfg.icloud_root) + ("  ✓" if icloud_exists else "  ✗ missing"))
    table.add_row("library",     str(cfg.library_dir) + ("  ✓" if library_exists else "  ✗ missing"))
    table.add_row("inbox",       str(cfg.inbox_dir)   + ("  ✓" if inbox_exists   else "  ✗ missing"))
    table.add_row("sqlite",      str(cfg.sqlite_path))
    table.add_row("papers",      str(paper_count))
    table.add_row("chunks",      str(chunk_count))
    table.add_row("claude CLI",     "available" if _claude_on_path() else "[red]missing — install Claude Code[/red]")
    table.add_row("ollama service", _check_ollama())
    console.print(table)


@app.command("rebuild-cache")
def rebuild_cache() -> None:
    """Drop the SQLite cache and rebuild from the iCloud library files."""
    cfg = config.load()
    storage.ensure_dirs(cfg)
    if cfg.sqlite_path.exists():
        cfg.sqlite_path.unlink()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    result = cache.rebuild(cfg, conn)
    conn.close()
    console.print(f"[green]✓[/green] rebuilt: {result['papers']} papers, {result['chunks']} chunks")
    for err in result.get("errors", []):
        console.print(f"[red]✗[/red] {err}")


@app.command("add-url")
def add_url(
    url: str = typer.Argument(..., help="arXiv URL/id, PDF URL, or any web page."),
    tags: str = typer.Option("", "--tags", help="Comma-separated user tags."),
) -> None:
    """Ingest from a URL — arXiv, direct PDF link, or any blog/article."""
    from . import fetch_url

    cfg = config.load()
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    tag_list = [t.strip() for t in tags.split(",") if t.strip()]

    console.print(f"fetching [bold]{url}[/bold]…")
    try:
        fetched = fetch_url.fetch(url)
    except Exception as e:
        console.print(f"[red]✗[/red] fetch failed: {e}")
        raise typer.Exit(code=1)

    if fetched.pdf_path:
        console.print(f"  pdf saved to {fetched.pdf_path} ({fetched.source_kind})")
        result = ingest.ingest_pdf(
            cfg, conn, fetched.pdf_path,
            user_tags=tag_list, source=f"{fetched.source_kind}:{fetched.source_url}",
        )
        fetched.pdf_path.unlink(missing_ok=True)
    else:
        console.print(f"  html → text ({len(fetched.text):,} chars)")
        result = ingest.ingest_text(
            cfg, conn,
            text=fetched.text,
            title_hint=fetched.title_hint,
            source_url=fetched.source_url,
            source_kind=fetched.source_kind,
            user_tags=tag_list,
        )
    state = "added" if result.new else "already in library"
    console.print(f"[green]✓[/green] {state}: [bold]{result.title}[/bold]  ({result.paper_id}, {result.chunk_count} chunks)")
    conn.close()


@app.command()
def publish(
    out: Path = typer.Option(Path.cwd() / "site", "--out", help="Static site output dir."),
    no_inbox: bool = typer.Option(False, "--no-inbox", help="Skip scanning the iCloud inbox."),
    no_push: bool = typer.Option(False, "--no-push", help="Build the site but don't git-push."),
    message: str = typer.Option(None, "-m", "--message", help="Commit message override."),
) -> None:
    """Full pipeline: scan inbox → export static site → commit + push to GitHub.

    Run this from inside the public site's git checkout (or pass --out pointing
    at it). Anything in iCloud `inbox/` gets ingested first, then the academic
    /papers page is rendered as plain HTML in the output dir.
    """
    from . import export_site as exporter

    cfg = config.load()
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)

    new_papers: list[tuple[str, str]] = []
    if not no_inbox:
        pdfs = sorted(cfg.inbox_dir.glob("*.pdf"))
        if pdfs:
            console.print(f"scanning inbox ({len(pdfs)} pdf(s))…")
            for p in pdfs:
                try:
                    r = ingest.ingest_pdf(cfg, conn, p)
                    tag = "new" if r.new else "dup"
                    console.print(f"  [{tag}] {r.title}  ({r.paper_id})")
                    if r.new:
                        new_papers.append((r.paper_id, r.title))
                        p.unlink(missing_ok=True)
                except Exception as e:
                    console.print(f"  [red]✗[/red] {p.name}: {e}")
        else:
            console.print("inbox empty")

    console.print(f"exporting static site → {out}…")
    result = exporter.export(cfg, conn, out)
    console.print(f"  rendered {result['papers']} paper(s)")
    conn.close()

    if no_push:
        console.print("[yellow]--no-push set — leaving the site uncommitted.[/yellow]")
        return

    import subprocess
    if not (out / ".git").exists():
        console.print(f"[yellow]{out} is not a git repo — skipping commit/push.[/yellow]")
        console.print("To enable auto-publish: `cd {0} && git init -b main && gh repo create ... --source . --push`".format(out))
        return

    try:
        subprocess.run(["git", "-C", str(out), "add", "-A"], check=True)
        status = subprocess.run(
            ["git", "-C", str(out), "status", "--porcelain"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        if not status:
            console.print("[blue]no changes to commit[/blue]")
            return
        if message is None:
            if new_papers:
                titles = ", ".join(t for _, t in new_papers[:3])
                more = "" if len(new_papers) <= 3 else f" (+{len(new_papers) - 3} more)"
                message = f"add: {titles}{more}"
            else:
                message = "update papers"
        subprocess.run(["git", "-C", str(out), "commit", "-m", message], check=True)
        subprocess.run(["git", "-C", str(out), "push"], check=True)
        console.print(f"[green]✓[/green] pushed: {message}")
    except subprocess.CalledProcessError as e:
        console.print(f"[red]✗[/red] git failed: {e}")
        raise typer.Exit(code=1)


@app.command()
def resummarize(
    paper_id: str = typer.Argument(None, help="Paper id. Omit + use --all to re-run every paper."),
    all_papers: bool = typer.Option(False, "--all", help="Re-summarize every paper in the library."),
) -> None:
    """Re-run Claude summarization on an existing paper using the current prompt.

    Useful after changing the summary template. Re-uses already-extracted text and
    embeddings — only the summary is regenerated.
    """
    cfg = config.load()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    if all_papers:
        rows = conn.execute("SELECT id, title FROM papers ORDER BY added_at").fetchall()
        if not rows:
            console.print("[yellow]library is empty[/yellow]")
            return
        for i, r in enumerate(rows, start=1):
            try:
                ingest.resummarize(cfg, conn, r["id"])
                console.print(f"[green]✓[/green] {i}/{len(rows)}  {r['title']}  ({r['id']})")
            except Exception as e:
                console.print(f"[red]✗[/red] {i}/{len(rows)}  {r['title']}: {e}")
    else:
        if not paper_id:
            console.print("[red]Provide a paper_id, or use --all.[/red]")
            raise typer.Exit(code=1)
        row = conn.execute("SELECT title FROM papers WHERE id = ?", (paper_id,)).fetchone()
        if not row:
            console.print(f"[red]no paper with id {paper_id}[/red]")
            raise typer.Exit(code=1)
        ingest.resummarize(cfg, conn, paper_id)
        console.print(f"[green]✓[/green] resummarized: {row['title']}  ({paper_id})")


@app.command()
def delete(
    paper_id: str = typer.Argument(...),
    yes: bool = typer.Option(False, "--yes", "-y", help="Skip confirmation."),
) -> None:
    """Delete a paper (PDF, summary, figures, embeddings) from the library."""
    cfg = config.load()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    row = conn.execute("SELECT title FROM papers WHERE id = ?", (paper_id,)).fetchone()
    if not row:
        console.print(f"[red]no paper with id {paper_id}[/red]")
        raise typer.Exit(code=1)
    if not yes and not typer.confirm(f"Delete '{row['title']}'? This removes PDF + summary + figures."):
        return
    title = library.delete(cfg, conn, paper_id)
    console.print(f"[green]✓[/green] deleted: {title}")


@app.command()
def kind(
    paper_id: str = typer.Argument(...),
    new_kind: str = typer.Argument(..., help="paper | book | report"),
) -> None:
    """Re-classify a paper as paper/book/report."""
    cfg = config.load()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    try:
        library.set_kind(cfg, conn, paper_id, new_kind)
    except library.LibraryError as e:
        console.print(f"[red]{e}[/red]")
        raise typer.Exit(code=1)
    console.print(f"[green]✓[/green] {paper_id} marked as {new_kind}")


@app.command()
def follow(
    category: str = typer.Argument(None, help="arXiv category code (e.g., cs.LG). Omit to list current follows."),
    remove: bool = typer.Option(False, "--remove", "-r", help="Remove instead of add."),
) -> None:
    """Manage which arXiv categories `paper discover` pulls from."""
    from . import discover as disc
    cfg = config.load()
    storage.ensure_dirs(cfg)
    if category is None:
        current = disc.list_follows(cfg)
        if not current:
            console.print("[yellow]no follows. add one with `paper follow cs.LG`[/yellow]")
        else:
            for c in current:
                console.print(f"  {c}")
        return
    if remove:
        new = disc.remove_follow(cfg, category)
        console.print(f"[green]✓[/green] removed {category} (now: {', '.join(new) or 'none'})")
    else:
        new = disc.add_follow(cfg, category)
        console.print(f"[green]✓[/green] added {category} (now: {', '.join(new)})")


@app.command()
def discover(
    per_category: int = typer.Option(30, "--per-category", help="How many recent arxiv papers to fetch per category."),
    top_k: int = typer.Option(12, "--top-k", help="How many top-ranked candidates to keep."),
) -> None:
    """Fetch new arXiv papers in followed categories, rank against your library."""
    from . import discover as disc
    cfg = config.load()
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    follows = disc.list_follows(cfg)
    if not follows:
        console.print("[yellow]no follows configured. add one: `paper follow cs.LG`[/yellow]")
        return
    console.print(f"fetching arXiv ({', '.join(follows)})…")
    candidates = disc.rank_and_save(cfg, conn, per_category=per_category, top_k=top_k)
    if not candidates:
        console.print("[yellow]no fresh candidates (already in library or interest vector empty)[/yellow]")
        return
    console.print(f"[green]✓[/green] saved {len(candidates)} candidate(s):")
    for c in candidates:
        console.print(f"  {c.score:.3f}  {c.title[:80]}  [{c.arxiv_id}]")


@app.command("classify-existing")
def classify_existing(
    threshold: int = typer.Option(80, "--threshold", help="Page count above which a PDF is treated as a book."),
) -> None:
    """Backfill: detect kind on every paper in the library via PyMuPDF page count."""
    import fitz  # fast page-count, no full text re-extract
    cfg = config.load()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    rows = conn.execute(
        "SELECT id, title, pages, kind FROM papers ORDER BY added_at"
    ).fetchall()
    if not rows:
        console.print("[yellow]library is empty[/yellow]")
        return
    relabeled = 0
    for r in rows:
        pages = r["pages"]
        if pages is None:
            pdf_path = storage.pdf_path(cfg, r["id"])
            if not pdf_path.exists():
                continue
            try:
                doc = fitz.open(str(pdf_path))
                pages = doc.page_count
                doc.close()
            except Exception as e:
                console.print(f"[red]✗[/red] {r['id']}  {e}")
                continue
        title_lc = (r["title"] or "").lower()
        if "technical report" in title_lc or title_lc.endswith(" report") or " report:" in title_lc:
            new = "report"
        elif pages > threshold:
            new = "book"
        else:
            new = "paper"
        current = r["kind"] or "paper"
        if new != current:
            library.set_kind(cfg, conn, r["id"], new)
            console.print(f"[yellow]{current}→{new}[/yellow]  {pages:>4}p  {r['title']}")
            relabeled += 1
        with conn:
            conn.execute("UPDATE papers SET pages = ? WHERE id = ?", (pages, r["id"]))
    console.print(f"\n[green]✓[/green] relabeled {relabeled}/{len(rows)} papers")


@app.command("export-site")
def export_site(
    out: Path = typer.Option(
        Path.cwd() / "site",
        "--out",
        help="Output directory for the static site.",
    ),
) -> None:
    """Render the /papers page (plus per-paper detail pages) to a static folder.

    The output directory is self-contained — point GitHub Pages at it, or
    commit it to whichever repo serves your public site.
    """
    from . import export_site as exporter

    cfg = config.load()
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    result = exporter.export(cfg, conn, out)
    conn.close()
    console.print(f"[green]✓[/green] exported {result['papers']} paper(s) to [bold]{result['out_dir']}[/bold]")
    console.print()
    console.print("Next: commit and push the site/ directory to your public repo.")


@app.command()
def serve(
    host: str = typer.Option("127.0.0.1", help="Bind address."),
    port: int = typer.Option(8765, help="Port."),
    reload: bool = typer.Option(False, "--reload", help="Auto-reload on code changes."),
) -> None:
    """Start the local web app."""
    import uvicorn

    uvicorn.run(
        "paper_manager.app:create_app",
        factory=True,
        host=host,
        port=port,
        reload=reload,
    )


@app.command("migrate-zotero")
def migrate_zotero(
    root: Path = typer.Option(
        Path("~/Library/Mobile Documents/com~apple~CloudDocs/zoteto_storage").expanduser(),
        "--root",
        help="Zotero storage root.",
    ),
    limit: int = typer.Option(0, "--limit", help="Stop after N papers (0 = all)."),
    skip: int = typer.Option(0, "--skip", help="Skip the first N PDFs."),
) -> None:
    """Bulk-import every PDF from a Zotero storage folder."""
    from .migrate.zotero import find_pdfs, migrate

    cfg = config.load()
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)

    pdfs = find_pdfs(root)
    total = len(pdfs)
    if not pdfs:
        console.print(f"[yellow]no PDFs found under {root}[/yellow]")
        return
    console.print(f"found {total} PDF(s) under [bold]{root}[/bold]")
    if skip:
        pdfs = pdfs[skip:]
        console.print(f"skipping first {skip}")
    if limit:
        pdfs = pdfs[:limit]
        console.print(f"will process {len(pdfs)} of {total - skip}")

    def ingest_one(pdf: Path):
        result = ingest.ingest_pdf(cfg, conn, pdf, source=f"zotero:{pdf.parent.name}")
        return result.paper_id, result.title, result.new

    new_count = dup_count = err_count = 0
    for i, pdf in enumerate(pdfs, start=1):
        try:
            paper_id, title, is_new = ingest_one(pdf)
            if is_new:
                new_count += 1
                console.print(f"[green]✓[/green] {skip + i}/{total} [new]  {title}  ({paper_id})")
            else:
                dup_count += 1
                console.print(f"[blue]·[/blue] {skip + i}/{total} [dup]  {title}  ({paper_id})")
        except Exception as e:
            err_count += 1
            console.print(f"[red]✗[/red] {skip + i}/{total} [err]  {pdf.name}: {e}")
    console.print()
    console.print(f"done. new={new_count}, dup={dup_count}, err={err_count}")


@app.command("sync-inbox")
def sync_inbox() -> None:
    """Ingest every PDF currently sitting in the iCloud inbox."""
    cfg = config.load()
    storage.ensure_dirs(cfg)
    conn = db.connect(cfg.sqlite_path)
    db.init_schema(conn)
    pdfs = sorted(cfg.inbox_dir.glob("*.pdf"))
    if not pdfs:
        console.print("[yellow]inbox is empty[/yellow]")
        return
    for p in pdfs:
        try:
            result = ingest.ingest_pdf(cfg, conn, p)
            state = "added" if result.new else "skip (dup)"
            console.print(f"[green]✓[/green] {state}: {result.title}  ({result.paper_id})")
            if result.new:
                p.unlink(missing_ok=True)
        except Exception as e:
            console.print(f"[red]✗[/red] {p.name}: {e}")
    conn.close()


if __name__ == "__main__":
    app()
