"""Local embeddings via Ollama (mxbai-embed-large by default, 1024-dim)."""
from __future__ import annotations

import os

import httpx
import numpy as np

DEFAULT_MODEL = "mxbai-embed-large"
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")


def embed_documents(texts: list[str], model: str = DEFAULT_MODEL) -> np.ndarray:
    return _embed(texts, model=model)


def embed_queries(texts: list[str], model: str = DEFAULT_MODEL) -> np.ndarray:
    return _embed(texts, model=model)


def embed_query(text: str, model: str = DEFAULT_MODEL) -> np.ndarray:
    return _embed([text], model=model)[0]


def _embed(texts: list[str], model: str) -> np.ndarray:
    """Embed texts, transparently retrying with harder trimming on context errors.

    mxbai-embed-large caps at 512 tokens. Dense scientific text hits ~3 chars/token,
    so 1024 chars is a safe initial target; if Ollama still complains we halve and
    retry once.
    """
    if not texts:
        return np.zeros((0, 1024), dtype=np.float32)
    out: list[list[float]] = []
    batch_size = 16
    for i in range(0, len(texts), batch_size):
        batch = texts[i : i + batch_size]
        out.extend(_embed_batch(batch, model, max_chars=1024))
    return np.asarray(out, dtype=np.float32)


def _embed_batch(batch: list[str], model: str, max_chars: int) -> list[list[float]]:
    if max_chars < 200:
        raise RuntimeError("could not fit batch into context even at 200 chars/text")
    trimmed = [_trim_to_context(t, max_chars=max_chars) for t in batch]
    r = httpx.post(
        f"{OLLAMA_HOST}/api/embed",
        json={"model": model, "input": trimmed},
        timeout=120.0,
    )
    if r.status_code == 400 and "exceeds the context length" in r.text:
        return _embed_batch(batch, model, max_chars=max_chars // 2)
    r.raise_for_status()
    embeddings = r.json().get("embeddings")
    if not embeddings:
        raise RuntimeError(f"ollama returned no embeddings: {r.text[:200]}")
    return embeddings


def _trim_to_context(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    half = max_chars // 2
    return text[:half] + "\n…\n" + text[-half:]
