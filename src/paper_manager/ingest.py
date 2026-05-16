from __future__ import annotations

import hashlib
import json
import sqlite3
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import claude, code_links, embed, figures, pdf, storage
from .config import Config
from .db import transaction, vector_to_blob
from .storage import PaperMeta, now_iso


@dataclass
class IngestResult:
    paper_id: str
    title: str
    new: bool
    chunk_count: int


def ingest_pdf(
    cfg: Config,
    conn: sqlite3.Connection,
    src_pdf: Path,
    *,
    user_tags: list[str] | None = None,
    source: str = "manual",
    force_resummarize: bool = False,
) -> IngestResult:
    if not src_pdf.exists():
        raise FileNotFoundError(src_pdf)

    sha = storage.sha256_of(src_pdf)
    paper_id = storage.paper_id_from_sha(sha)

    already = conn.execute("SELECT id, title FROM papers WHERE id = ?", (paper_id,)).fetchone()
    if already and not force_resummarize:
        if user_tags:
            _merge_user_tags(conn, paper_id, user_tags)
        return IngestResult(paper_id=paper_id, title=already["title"], new=False, chunk_count=0)

    storage.copy_pdf(cfg, src_pdf, paper_id)

    extracted = pdf.extract(storage.pdf_path(cfg, paper_id))
    storage.write_text(cfg, paper_id, extracted.full_text)

    try:
        figures.extract(storage.pdf_path(cfg, paper_id), storage.figures_dir(cfg, paper_id))
    except Exception:
        pass  # never let a figure extraction failure block the ingest

    kind = pdf.detect_kind(extracted, title_hint=src_pdf.stem)
    if kind != "paper":
        # Books and reports don't fit the Keshav three-pass framing. We still
        # extract text + figures + embeddings (so they're searchable), but skip
        # the expensive Claude pass and fill metadata from filename only.
        title = src_pdf.stem
        authors: list[str] = []
        year = None
        venue = None
        doi = None
        arxiv_id = None
        auto: dict = {"tags": [], "methods": [], "datasets": [], "claims": [], "key_terms": [], "code_links": []}
        summary = f"*This is a {kind}, not a research paper. Summary skipped.*"
    else:
        raw = claude.summarize_and_extract(
            extracted.full_text,
            title_hint=src_pdf.stem,
            model=cfg.claude_model,
        )
        title = raw.get("title") or src_pdf.stem
        authors = raw.get("authors") or []
        year = raw.get("year")
        venue = raw.get("venue")
        doi = raw.get("doi")
        arxiv_id = raw.get("arxiv_id")
        auto = raw.get("auto") or {}
        summary = raw.get("summary") or ""
    auto["code_links"] = code_links.merge_with_claude(
        code_links.find(extracted.full_text),
        auto.get("code_links"),
    )
    storage.write_summary(cfg, paper_id, summary)

    chunks = [c for c in pdf.chunk(extracted) if c.get("text", "").strip()]
    for i, c in enumerate(chunks):
        c["idx"] = i
    storage.write_chunks(cfg, paper_id, chunks)

    chunk_texts = [c["text"] for c in chunks]
    chunk_vectors = (
        embed.embed_documents(chunk_texts, model=cfg.embed_model)
        if chunk_texts
        else np.zeros((0, 1024), dtype=np.float32)
    )

    summary_for_embed = summary.strip() or title
    summary_vec = embed.embed_documents([summary_for_embed], model=cfg.embed_model)[0]

    meta = PaperMeta(
        id=paper_id,
        title=title,
        authors=authors,
        year=year,
        venue=venue,
        doi=doi,
        arxiv_id=arxiv_id,
        added_at=now_iso(),
        sha256=sha,
        source=source,
        kind=kind,
        pages=extracted.page_count,
        user_tags=user_tags or [],
        auto=auto,
    )
    storage.write_metadata(cfg, meta)

    with transaction(conn):
        conn.execute("DELETE FROM chunks WHERE paper_id = ?", (paper_id,))
        conn.execute(
            """
            INSERT INTO papers(
                id, title, authors, year, venue, doi, arxiv_id,
                added_at, sha256, source, kind, pages, user_tags, auto, summary, summary_vec
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                authors=excluded.authors,
                year=excluded.year,
                venue=excluded.venue,
                doi=excluded.doi,
                arxiv_id=excluded.arxiv_id,
                kind=excluded.kind,
                pages=excluded.pages,
                user_tags=excluded.user_tags,
                auto=excluded.auto,
                summary=excluded.summary,
                summary_vec=excluded.summary_vec
            """,
            (
                paper_id,
                title,
                json.dumps(authors),
                year,
                venue,
                doi,
                arxiv_id,
                meta.added_at,
                sha,
                source,
                kind,
                extracted.page_count,
                json.dumps(meta.user_tags),
                json.dumps(auto),
                summary,
                vector_to_blob(summary_vec),
            ),
        )
        for c, v in zip(chunks, chunk_vectors):
            conn.execute(
                "INSERT INTO chunks(paper_id, idx, text, page_start, page_end, vector) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (
                    paper_id,
                    c["idx"],
                    c["text"],
                    c.get("page_start"),
                    c.get("page_end"),
                    vector_to_blob(v),
                ),
            )
        conn.execute(
            "DELETE FROM chunks_fts WHERE paper_id = ?",
            (paper_id,),
        )
        for c in chunks:
            conn.execute(
                "INSERT INTO chunks_fts(text, paper_id, idx) VALUES (?, ?, ?)",
                (c["text"], paper_id, c["idx"]),
            )

    return IngestResult(paper_id=paper_id, title=title, new=True, chunk_count=len(chunks))


def ingest_text(
    cfg: Config,
    conn: sqlite3.Connection,
    *,
    text: str,
    title_hint: str | None,
    source_url: str,
    source_kind: str,
    user_tags: list[str] | None = None,
) -> IngestResult:
    """Ingest a non-PDF source (HTML / blog post) given its extracted text.

    paper_id is sha256(text + source_url)[:12] so the same URL doesn't dup-ingest.
    No PDF is stored — the source_url in metadata points back to the original.
    """
    if not text.strip():
        raise ValueError("empty text")
    fingerprint = hashlib.sha256((source_url + "\n" + text).encode("utf-8")).hexdigest()
    paper_id = storage.paper_id_from_sha(fingerprint)

    already = conn.execute("SELECT id, title FROM papers WHERE id = ?", (paper_id,)).fetchone()
    if already:
        if user_tags:
            _merge_user_tags(conn, paper_id, user_tags)
        return IngestResult(paper_id=paper_id, title=already["title"], new=False, chunk_count=0)

    pdir = storage.paper_dir(cfg, paper_id)
    pdir.mkdir(parents=True, exist_ok=True)
    storage.write_text(cfg, paper_id, text)

    raw = claude.summarize_and_extract(text, title_hint=title_hint, model=cfg.claude_model)
    title = raw.get("title") or title_hint or "Untitled"
    authors = raw.get("authors") or []
    year = raw.get("year")
    venue = raw.get("venue") or _venue_from_url(source_url)
    doi = raw.get("doi")
    arxiv_id = raw.get("arxiv_id")
    auto = raw.get("auto") or {}
    summary = raw.get("summary") or ""
    auto["code_links"] = code_links.merge_with_claude(
        code_links.find(text), auto.get("code_links"),
    )
    storage.write_summary(cfg, paper_id, summary)

    extracted = pdf.ExtractedPdf(full_text=text, pages=[pdf.PageText(page=1, text=text)], page_count=1)
    chunks = [c for c in pdf.chunk(extracted) if c.get("text", "").strip()]
    for i, c in enumerate(chunks):
        c["idx"] = i
    storage.write_chunks(cfg, paper_id, chunks)

    chunk_texts = [c["text"] for c in chunks]
    chunk_vectors = (
        embed.embed_documents(chunk_texts, model=cfg.embed_model)
        if chunk_texts
        else np.zeros((0, 1024), dtype=np.float32)
    )
    summary_vec = embed.embed_documents([summary or title], model=cfg.embed_model)[0]

    meta = PaperMeta(
        id=paper_id,
        title=title,
        authors=authors,
        year=year,
        venue=venue,
        doi=doi,
        arxiv_id=arxiv_id,
        added_at=now_iso(),
        sha256=fingerprint,
        source=f"{source_kind}:{source_url}",
        user_tags=user_tags or [],
        auto=auto,
    )
    storage.write_metadata(cfg, meta)

    with transaction(conn):
        conn.execute("DELETE FROM chunks WHERE paper_id = ?", (paper_id,))
        conn.execute(
            """
            INSERT INTO papers(
                id, title, authors, year, venue, doi, arxiv_id,
                added_at, sha256, source, user_tags, auto, summary, summary_vec
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title, authors=excluded.authors, year=excluded.year,
                venue=excluded.venue, doi=excluded.doi, arxiv_id=excluded.arxiv_id,
                user_tags=excluded.user_tags, auto=excluded.auto,
                summary=excluded.summary, summary_vec=excluded.summary_vec
            """,
            (
                paper_id, title, json.dumps(authors), year, venue, doi, arxiv_id,
                meta.added_at, fingerprint, meta.source,
                json.dumps(meta.user_tags), json.dumps(auto), summary, vector_to_blob(summary_vec),
            ),
        )
        for c, v in zip(chunks, chunk_vectors):
            conn.execute(
                "INSERT INTO chunks(paper_id, idx, text, page_start, page_end, vector) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (paper_id, c["idx"], c["text"], c.get("page_start"), c.get("page_end"), vector_to_blob(v)),
            )
            conn.execute(
                "INSERT INTO chunks_fts(text, paper_id, idx) VALUES (?, ?, ?)",
                (c["text"], paper_id, c["idx"]),
            )
    return IngestResult(paper_id=paper_id, title=title, new=True, chunk_count=len(chunks))


def _venue_from_url(url: str) -> str | None:
    from urllib.parse import urlparse
    host = urlparse(url).netloc.replace("www.", "")
    return host if host else None


def resummarize(
    cfg: Config,
    conn: sqlite3.Connection,
    paper_id: str,
) -> str:
    """Re-run Claude summarization for an existing paper without re-embedding.

    Reads `text.txt` from iCloud, calls Claude with the current SUMMARY_SYSTEM
    prompt, overwrites `summary.md` on disk, and updates the SQLite mirror.
    """
    pdf_path = storage.pdf_path(cfg, paper_id)
    if not pdf_path.exists():
        raise FileNotFoundError(f"no PDF for {paper_id}")
    text_path = storage.text_path(cfg, paper_id)
    paper_text = text_path.read_text() if text_path.exists() else pdf.extract(pdf_path).full_text

    title_row = conn.execute("SELECT title FROM papers WHERE id = ?", (paper_id,)).fetchone()
    title_hint = title_row["title"] if title_row else None

    summary = claude._run(
        (
            f"Write the structured summary for this paper following the three-pass method. "
            f"Title hint (may be wrong or absent): {title_hint or 'unknown'}\n\n"
            f"---\n\n{paper_text[:60_000]}\n\n---\n\n"
            f"Output only the Markdown template, no preamble."
        ),
        system=claude.SUMMARY_SYSTEM,
        model=cfg.claude_model,
    )
    storage.write_summary(cfg, paper_id, summary)
    conn.execute("UPDATE papers SET summary = ? WHERE id = ?", (summary, paper_id))
    conn.commit()
    return summary


def _merge_user_tags(conn: sqlite3.Connection, paper_id: str, new_tags: list[str]) -> None:
    row = conn.execute("SELECT user_tags FROM papers WHERE id = ?", (paper_id,)).fetchone()
    if not row:
        return
    existing = set(json.loads(row["user_tags"]))
    merged = sorted(existing | set(t.strip() for t in new_tags if t.strip()))
    conn.execute("UPDATE papers SET user_tags = ? WHERE id = ?", (json.dumps(merged), paper_id))
    conn.commit()
