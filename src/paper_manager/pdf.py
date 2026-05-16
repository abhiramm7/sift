from __future__ import annotations

from dataclasses import dataclass
from io import StringIO
from pathlib import Path

from pdfminer.high_level import extract_text_to_fp
from pdfminer.layout import LAParams
from pypdf import PdfReader


@dataclass
class PageText:
    page: int
    text: str


@dataclass
class ExtractedPdf:
    full_text: str
    pages: list[PageText]
    page_count: int


def extract(path: Path) -> ExtractedPdf:
    pages = _extract_with_pypdf(path)
    if _suspicious(pages):
        fallback = _extract_with_pdfminer(path)
        if _better(fallback, pages):
            pages = fallback
    full = "\n\n".join(p.text for p in pages).strip()
    return ExtractedPdf(full_text=full, pages=pages, page_count=len(pages))


# Heuristic: longer than BOOK_THRESHOLD pages → treat as a book (no Keshav summary,
# since books don't fit the three-pass framing). "Report" wins via the title check.
BOOK_THRESHOLD_PAGES = 80


def detect_kind(extracted: "ExtractedPdf", title_hint: str | None = None) -> str:
    """Classify a PDF as 'paper', 'book', or 'report'."""
    title = (title_hint or "").lower()
    if "technical report" in title or title.endswith(" report") or " report:" in title:
        return "report"
    if extracted.page_count > BOOK_THRESHOLD_PAGES:
        return "book"
    return "paper"


def _extract_with_pypdf(path: Path) -> list[PageText]:
    reader = PdfReader(str(path))
    out: list[PageText] = []
    for i, page in enumerate(reader.pages, start=1):
        try:
            text = page.extract_text() or ""
        except Exception:
            text = ""
        out.append(PageText(page=i, text=text.strip()))
    return out


def _extract_with_pdfminer(path: Path) -> list[PageText]:
    buffer = StringIO()
    with path.open("rb") as f:
        extract_text_to_fp(f, buffer, laparams=LAParams())
    raw = buffer.getvalue()
    raw_pages = raw.split("\x0c")
    pages: list[PageText] = []
    page_num = 1
    for p in raw_pages:
        t = p.strip()
        if not t and page_num == len(raw_pages):
            break
        pages.append(PageText(page=page_num, text=t))
        page_num += 1
    return pages


def _suspicious(pages: list[PageText]) -> bool:
    if not pages:
        return True
    total = sum(len(p.text) for p in pages)
    avg = total / len(pages)
    return total < 500 or avg < 50


def _better(candidate: list[PageText], current: list[PageText]) -> bool:
    return sum(len(p.text) for p in candidate) > sum(len(p.text) for p in current)


def chunk(
    extracted: ExtractedPdf,
    target_chars: int = 1200,
    overlap_chars: int = 150,
) -> list[dict]:
    """Page-aware chunking. ~300 tokens ≈ 1200 chars for English text.

    Sized to fit safely under mxbai-embed-large's 512-token context window
    even for dense scientific prose (which can hit ~3 chars/token).
    """
    chunks: list[dict] = []
    if not extracted.pages:
        return chunks

    buf: list[tuple[int, str]] = []
    buf_len = 0

    def flush() -> None:
        nonlocal buf, buf_len
        if not buf:
            return
        text = "\n\n".join(t for _, t in buf).strip()
        if not text:
            buf = []
            buf_len = 0
            return
        start = buf[0][0]
        end = buf[-1][0]
        chunks.append(
            {
                "idx": len(chunks),
                "text": text,
                "page_start": start,
                "page_end": end,
            }
        )
        if overlap_chars > 0 and buf:
            tail_text = text[-overlap_chars:]
            tail_page = buf[-1][0]
            buf = [(tail_page, tail_text)]
            buf_len = len(tail_text)
        else:
            buf = []
            buf_len = 0

    for page in extracted.pages:
        ptext = page.text.strip()
        if not ptext:
            continue
        if buf_len + len(ptext) <= target_chars:
            buf.append((page.page, ptext))
            buf_len += len(ptext)
            continue

        if buf and buf_len >= target_chars // 2:
            flush()

        if len(ptext) > target_chars:
            i = 0
            while i < len(ptext):
                slab = ptext[i : i + target_chars]
                if buf:
                    flush()
                chunks.append(
                    {
                        "idx": len(chunks),
                        "text": slab.strip(),
                        "page_start": page.page,
                        "page_end": page.page,
                    }
                )
                i += target_chars - overlap_chars
            buf = []
            buf_len = 0
        else:
            if buf:
                flush()
            buf.append((page.page, ptext))
            buf_len = len(ptext)

    if buf:
        flush()

    for i, c in enumerate(chunks):
        c["idx"] = i
    return chunks
