"""Find code repository / implementation links in paper text.

Deterministic, regex-based. Runs after PDF text extraction and complements
whatever Claude turns up in the metadata pass.
"""
from __future__ import annotations

import re

# Hosts that almost always indicate "this is the code for the paper". We list
# them in priority order so we can hint at which one is the canonical repo.
_HOST_PATTERNS = [
    # GitHub: org/repo, optional subpath
    (r"https?://github\.com/([\w.-]+)/([\w.-]+)(?:/[\w./%#-]*)?", "github"),
    (r"https?://gitlab\.com/([\w./-]+)/([\w.-]+)(?:/[\w./%#-]*)?", "gitlab"),
    (r"https?://bitbucket\.org/([\w.-]+)/([\w.-]+)(?:/[\w./%#-]*)?", "bitbucket"),
    (r"https?://huggingface\.co/(?:datasets/|spaces/)?([\w.-]+)/([\w.-]+)(?:/[\w./%#-]*)?", "huggingface"),
    (r"https?://(?:www\.)?paperswithcode\.com/paper/[\w-]+", "paperswithcode"),
    (r"https?://(?:www\.)?zenodo\.org/record/\d+(?:/[\w./-]*)?", "zenodo"),
    (r"https?://(?:www\.)?colab\.research\.google\.com/[\w./-]+", "colab"),
]

# Common PDF cruft to strip from the end of a URL.
_TRAILING_JUNK = ".,;:)”’»"

_PLACEHOLDER_RE = re.compile(r"github\.com/(?:user|username|anonymous|XXX|TODO|YOUR-?USER)", re.I)


def find(text: str) -> list[dict]:
    """Return de-duplicated code links sorted by host priority then appearance order."""
    if not text:
        return []
    found: dict[str, dict] = {}
    for pattern, host in _HOST_PATTERNS:
        for m in re.finditer(pattern, text):
            url = _clean(m.group(0))
            if not url or _PLACEHOLDER_RE.search(url):
                continue
            if url in found:
                continue
            found[url] = {"url": url, "host": host}
    return list(found.values())


def _clean(url: str) -> str:
    url = url.strip()
    # PDFs sometimes break URLs across lines — strip whitespace if any sneaks in.
    url = re.sub(r"\s+", "", url)
    while url and url[-1] in _TRAILING_JUNK:
        url = url[:-1]
    return url


def merge_with_claude(
    regex_links: list[dict],
    claude_links: list[str] | None,
) -> list[dict]:
    """Combine regex-detected links with whatever Claude returned in metadata."""
    by_url = {entry["url"]: entry for entry in regex_links}
    for raw in claude_links or []:
        url = _clean(str(raw))
        if not url or _PLACEHOLDER_RE.search(url):
            continue
        if url not in by_url:
            by_url[url] = {"url": url, "host": _host_from_url(url)}
    return list(by_url.values())


def _host_from_url(url: str) -> str:
    m = re.match(r"https?://(?:www\.)?([^/]+)/?", url)
    return m.group(1) if m else "unknown"
