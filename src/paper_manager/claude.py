from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Iterable


def _load_prompt(name: str) -> str:
    """Load a prompt file from the repo's `prompts/` directory.

    Searches upward from this file so the prompt file is the same one users
    can edit directly to change LLM behavior — paper_manager and any external
    LLM share one source of truth.
    """
    here = Path(__file__).resolve()
    for parent in (here.parent, *here.parents):
        candidate = parent / "prompts" / name
        if candidate.exists():
            return candidate.read_text(encoding="utf-8")
    raise FileNotFoundError(f"could not find prompts/{name} near {here}")


SUMMARY_SYSTEM = _load_prompt("keshav-three-pass.md")


METADATA_SYSTEM = """You extract structured metadata from a scientific paper.

Return ONLY a JSON object matching this schema (no prose, no code fences):

{
  "title": string,
  "authors": string[],
  "year": integer | null,
  "venue": string | null,
  "doi": string | null,
  "arxiv_id": string | null,
  "auto": {
    "tags": string[],          // 3-6 short kebab-case topical tags
    "methods": string[],       // concrete methods / techniques used
    "datasets": string[],      // datasets evaluated on, if any
    "claims": string[],        // 2-5 key claims, each one sentence
    "key_terms": string[],     // distinctive terminology
    "code_links": string[]     // URLs of code repos / implementations referenced by the paper (github, gitlab, huggingface, paperswithcode, etc.) — empty array if none
  }
}

Inside string values: use ONLY straight ASCII double quotes for the JSON itself; for any quotation inside a value, use single quotes or curly quotes ('like this') instead. If a field is unknown, use null (scalars) or [] (arrays). Never invent."""


RECOMMEND_SYSTEM = """You recommend papers from the user's library. Given papers the user liked and a candidate pool of unread papers, pick the top n candidates the user would most enjoy and explain why in one sentence each.

Return ONLY a JSON array (no prose, no code fences), each element {"paper_id": string, "reason": string}. Use only paper_ids from the candidates list."""


CHAT_SYSTEM = """You are the user's personal research assistant for their paper library. You answer questions about papers in their library, helping them search, compare, and understand.

You will be given a small set of relevant chunks from the library along with each user message. Ground your answers in those chunks. Cite paper IDs in square brackets like [abc123def456]. If the provided context does not answer the question, say so plainly — do not invent papers, authors, numbers, or claims. Keep answers concise."""


class ClaudeCliError(RuntimeError):
    pass


def _claude_path() -> str:
    path = shutil.which("claude")
    if not path:
        raise ClaudeCliError(
            "The `claude` CLI is not on PATH. Install Claude Code and sign in: "
            "https://claude.com/claude-code"
        )
    return path


def _run(
    prompt: str,
    *,
    system: str,
    model: str,
    max_chars: int = 200_000,
) -> str:
    """Invoke `claude -p` headlessly, return stdout text."""
    if len(prompt) > max_chars:
        prompt = prompt[:max_chars]
    cmd = [
        _claude_path(),
        "-p",
        "--system-prompt", system,
        "--model", model,
        "--tools", "",
        "--no-session-persistence",
        "--output-format", "text",
        "--permission-mode", "bypassPermissions",
    ]
    try:
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            check=False,
            timeout=300,
        )
    except subprocess.TimeoutExpired as e:
        raise ClaudeCliError(f"claude CLI timed out after 5 min") from e
    if result.returncode != 0:
        raise ClaudeCliError(
            f"claude CLI exited {result.returncode}\nstderr: {result.stderr.strip()[:400]}"
        )
    return result.stdout.strip()


def summarize_and_extract(
    paper_text: str,
    *,
    title_hint: str | None = None,
    model: str = "claude-sonnet-4-6",
    max_input_chars: int = 60_000,
) -> dict:
    """Two CLI calls: one for the markdown summary, one for the JSON metadata.

    Split intentionally — Claude often forgets to escape literal quotes inside
    long markdown strings when asked to embed them in JSON, which corrupts the
    whole payload. Plain markdown + small JSON sidesteps the issue.
    """
    trimmed = paper_text[:max_input_chars]
    summary = _run(
        (
            f"Write the structured summary for this paper. "
            f"Title hint (may be wrong or absent): {title_hint or 'unknown'}\n\n"
            f"---\n\n{trimmed}\n\n---\n\n"
            f"Output only the Markdown template, no preamble."
        ),
        system=SUMMARY_SYSTEM,
        model=model,
    )
    meta_raw = _run(
        (
            f"Extract metadata from this paper.\n\n"
            f"---\n\n{trimmed}\n\n---\n\n"
            f"Return only the JSON object."
        ),
        system=METADATA_SYSTEM,
        model=model,
    )
    meta = _parse_json(meta_raw)
    if not isinstance(meta, dict):
        meta = {}
    meta.setdefault("title", title_hint or "Untitled")
    meta.setdefault("authors", [])
    meta.setdefault("year", None)
    meta.setdefault("venue", None)
    meta.setdefault("doi", None)
    meta.setdefault("arxiv_id", None)
    auto = meta.setdefault("auto", {})
    for k in ("tags", "methods", "datasets", "claims", "key_terms", "code_links"):
        auto.setdefault(k, [])
    meta["summary"] = summary
    return meta


def recommend(
    liked: list[dict],
    candidates: list[dict],
    *,
    model: str = "claude-sonnet-4-6",
    n: int = 5,
) -> list[dict]:
    if not candidates:
        return []
    payload = {"liked": liked, "candidates": candidates, "n": n}
    prompt = (
        f"Pick {n} candidates the user would most enjoy. Use only paper_ids from candidates. "
        f"Input follows.\n\n{json.dumps(payload, ensure_ascii=False)}\n\n"
        f"Return only the JSON array."
    )
    raw = _run(prompt, system=RECOMMEND_SYSTEM, model=model)
    parsed = _parse_json(raw)
    if isinstance(parsed, list):
        return parsed
    if isinstance(parsed, dict) and "recommendations" in parsed:
        return parsed["recommendations"]
    return []


def chat(
    history: Iterable[dict],
    user_message: str,
    library_context: str,
    *,
    model: str = "claude-sonnet-4-6",
) -> str:
    """Single Claude call for a chat turn, with pre-fetched library context."""
    convo_lines: list[str] = []
    for msg in history:
        role = msg.get("role", "user")
        content = msg.get("content", "")
        if isinstance(content, list):
            text_parts = [
                b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"
            ]
            content = " ".join(t for t in text_parts if t)
        if content:
            convo_lines.append(f"{role.upper()}: {content}")
    convo = "\n\n".join(convo_lines)
    parts: list[str] = []
    if convo:
        parts.append("PREVIOUS CONVERSATION:\n" + convo)
    parts.append("LIBRARY CONTEXT (top relevant chunks from the user's library):\n" + library_context)
    parts.append("USER MESSAGE:\n" + user_message)
    parts.append(
        "Respond to the user message. Ground your answer in the library context above; "
        "cite paper IDs in [brackets]. If the context doesn't cover the question, say so."
    )
    prompt = "\n\n---\n\n".join(parts)
    return _run(prompt, system=CHAT_SYSTEM, model=model)


def _parse_json(raw: str):
    raw = raw.strip()
    if raw.startswith("```"):
        lines = raw.splitlines()
        lines = [ln for ln in lines if not ln.startswith("```")]
        raw = "\n".join(lines).strip()
    start_obj = raw.find("{")
    start_arr = raw.find("[")
    starts = [s for s in (start_obj, start_arr) if s != -1]
    if not starts:
        return {}
    start = min(starts)
    end = max(raw.rfind("}"), raw.rfind("]"))
    if end <= start:
        return {}
    try:
        return json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return {}
