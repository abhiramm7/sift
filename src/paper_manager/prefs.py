from __future__ import annotations

import json
import sqlite3

from .config import Config
from .storage import now_iso


def set_rating(
    cfg: Config,
    conn: sqlite3.Connection,
    paper_id: str,
    rating: int | None,
) -> None:
    """rating: -1 (down), 1 (up), 2..5 (stars), or None to clear."""
    if rating is not None and rating not in (-1, 1, 2, 3, 4, 5):
        raise ValueError(f"invalid rating: {rating}")
    conn.execute(
        """
        INSERT INTO prefs(paper_id, rating, updated_at)
        VALUES(?, ?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET rating = excluded.rating, updated_at = excluded.updated_at
        """,
        (paper_id, rating, now_iso()),
    )
    conn.commit()
    _flush_to_icloud(cfg, conn)
    _invalidate_recs(conn, ("claude_picks", "because_you_liked", "from_your_favorite_tags"))


def set_flag(
    cfg: Config,
    conn: sqlite3.Connection,
    paper_id: str,
    *,
    saved: bool | None = None,
    hidden: bool | None = None,
    read: bool | None = None,
) -> None:
    fields = []
    values: list = []
    if saved is not None:
        fields.append("saved = ?")
        values.append(1 if saved else 0)
    if hidden is not None:
        fields.append("hidden = ?")
        values.append(1 if hidden else 0)
    if read is not None:
        fields.append("read = ?")
        values.append(1 if read else 0)
    if not fields:
        return
    fields.append("updated_at = ?")
    values.append(now_iso())

    conn.execute(
        f"""
        INSERT INTO prefs(paper_id, saved, hidden, read, updated_at)
        VALUES(?, ?, ?, ?, ?)
        ON CONFLICT(paper_id) DO UPDATE SET {", ".join(fields)}
        """,
        (
            paper_id,
            1 if saved else 0,
            1 if hidden else 0,
            1 if read else 0,
            now_iso(),
            *values,
        ),
    )
    conn.commit()
    _flush_to_icloud(cfg, conn)
    _invalidate_recs(conn, ("continue_reading",))


def log_event(
    cfg: Config,
    conn: sqlite3.Connection,
    paper_id: str,
    event: str,
) -> None:
    ts = now_iso()
    conn.execute(
        "INSERT INTO history(paper_id, event, ts) VALUES(?, ?, ?)",
        (paper_id, event, ts),
    )
    conn.commit()
    cfg.history_path.parent.mkdir(parents=True, exist_ok=True)
    with cfg.history_path.open("a") as f:
        f.write(json.dumps({"paper_id": paper_id, "event": event, "ts": ts}) + "\n")
    _invalidate_recs(conn, ("continue_reading",))


def get_prefs(conn: sqlite3.Connection, paper_id: str) -> dict:
    row = conn.execute("SELECT * FROM prefs WHERE paper_id = ?", (paper_id,)).fetchone()
    if not row:
        return {"rating": None, "saved": False, "hidden": False, "read": False}
    return {
        "rating": row["rating"],
        "saved": bool(row["saved"]),
        "hidden": bool(row["hidden"]),
        "read": bool(row["read"]),
    }


def _flush_to_icloud(cfg: Config, conn: sqlite3.Connection) -> None:
    rows = conn.execute("SELECT * FROM prefs").fetchall()
    payload = {
        r["paper_id"]: {
            "rating": r["rating"],
            "saved": bool(r["saved"]),
            "hidden": bool(r["hidden"]),
            "read": bool(r["read"]),
            "updated_at": r["updated_at"],
        }
        for r in rows
    }
    cfg.prefs_path.parent.mkdir(parents=True, exist_ok=True)
    cfg.prefs_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False))


def load_from_icloud(cfg: Config, conn: sqlite3.Connection) -> int:
    """Rehydrate prefs + history from iCloud files. Used on first run / cache rebuild."""
    count = 0
    if cfg.prefs_path.exists():
        data = json.loads(cfg.prefs_path.read_text() or "{}")
        for pid, p in data.items():
            conn.execute(
                """
                INSERT INTO prefs(paper_id, rating, saved, hidden, read, updated_at)
                VALUES(?, ?, ?, ?, ?, ?)
                ON CONFLICT(paper_id) DO UPDATE SET
                    rating = excluded.rating,
                    saved = excluded.saved,
                    hidden = excluded.hidden,
                    read = excluded.read,
                    updated_at = excluded.updated_at
                """,
                (
                    pid,
                    p.get("rating"),
                    1 if p.get("saved") else 0,
                    1 if p.get("hidden") else 0,
                    1 if p.get("read") else 0,
                    p.get("updated_at", now_iso()),
                ),
            )
            count += 1
    if cfg.history_path.exists():
        for line in cfg.history_path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            conn.execute(
                "INSERT INTO history(paper_id, event, ts) VALUES(?, ?, ?)",
                (ev["paper_id"], ev["event"], ev["ts"]),
            )
    conn.commit()
    return count


def _invalidate_recs(conn: sqlite3.Connection, keys: tuple[str, ...]) -> None:
    for k in keys:
        conn.execute("DELETE FROM recs_cache WHERE row_key = ?", (k,))
    conn.commit()
