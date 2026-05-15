"""Fetch a URL and produce a (text, optional_pdf_path, source_metadata) tuple.

Handles three cases:
 1. arXiv URL / id      → download the PDF and extract via the normal PDF pipeline
 2. Direct PDF URL      → download the PDF
 3. HTML (blog / page)  → readability extraction of main content
"""
from __future__ import annotations

import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

import httpx
from readability import Document

USER_AGENT = "paper_manager/0.1 (+local)"


@dataclass
class FetchResult:
    """Either a downloaded PDF path or extracted plain text — never both for now."""
    text: str
    pdf_path: Path | None
    title_hint: str | None
    source_url: str
    source_kind: str  # "arxiv" | "pdf" | "html"


def fetch(url: str) -> FetchResult:
    arxiv_id = _arxiv_id(url)
    if arxiv_id:
        return _fetch_arxiv(arxiv_id)
    if _looks_like_pdf_url(url):
        return _fetch_pdf(url)
    return _fetch_html(url)


def _arxiv_id(url: str) -> str | None:
    m = re.search(r"arxiv\.org/(?:abs|pdf|html)/([\d\.]+)(?:v\d+)?", url, re.IGNORECASE)
    if m:
        return m.group(1)
    m = re.match(r"^([\d]{4}\.[\d]{4,5})(?:v\d+)?$", url.strip())
    if m:
        return m.group(1)
    return None


def _fetch_arxiv(arxiv_id: str) -> FetchResult:
    pdf_url = f"https://arxiv.org/pdf/{arxiv_id}.pdf"
    path = _download_pdf(pdf_url)
    return FetchResult(
        text="",
        pdf_path=path,
        title_hint=None,
        source_url=f"https://arxiv.org/abs/{arxiv_id}",
        source_kind="arxiv",
    )


def _fetch_pdf(url: str) -> FetchResult:
    path = _download_pdf(url)
    return FetchResult(
        text="",
        pdf_path=path,
        title_hint=None,
        source_url=url,
        source_kind="pdf",
    )


def _download_pdf(url: str) -> Path:
    with httpx.Client(
        follow_redirects=True,
        timeout=60.0,
        headers={"User-Agent": USER_AGENT},
    ) as client:
        r = client.get(url)
        r.raise_for_status()
    fd, tmp = tempfile.mkstemp(suffix=".pdf")
    Path(tmp).write_bytes(r.content)
    return Path(tmp)


def _fetch_html(url: str) -> FetchResult:
    with httpx.Client(
        follow_redirects=True,
        timeout=30.0,
        headers={"User-Agent": USER_AGENT},
    ) as client:
        r = client.get(url)
        r.raise_for_status()
        html = r.text
    doc = Document(html)
    title = doc.title() or _slug_from_url(url)
    main_html = doc.summary(html_partial=True)
    text = _html_to_text(main_html)
    return FetchResult(
        text=text,
        pdf_path=None,
        title_hint=title,
        source_url=url,
        source_kind="html",
    )


def _html_to_text(html: str) -> str:
    from lxml import html as lxhtml

    tree = lxhtml.fromstring(html)
    parts: list[str] = []
    for elem in tree.iter():
        if elem.tag in ("script", "style"):
            continue
        if elem.text:
            parts.append(elem.text)
        if elem.tail:
            parts.append(elem.tail)
    text = " ".join(p.strip() for p in parts if p and p.strip())
    return re.sub(r"\s+", " ", text).strip()


def _looks_like_pdf_url(url: str) -> bool:
    return urlparse(url).path.lower().endswith(".pdf")


def _slug_from_url(url: str) -> str:
    parsed = urlparse(url)
    parts = [p for p in parsed.path.split("/") if p]
    return parts[-1] if parts else parsed.netloc
