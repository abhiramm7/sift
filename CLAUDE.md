# Paper Manager — agent notes

Personal research library. Two coexisting frontends share the **same on-disk format** in iCloud Drive:

- **Python CLI / FastAPI web app** (`src/paper_manager/`, command `paper`) — LLM-driven: Claude summaries, Ollama embeddings, search, recommendations, arXiv discovery, static-site export.
- **Native macOS SwiftUI app** (`macapp/`) — standalone catalog: ingest, tag, rate, read/unread, search. No Python required. Released as `PaperManager-0.1.0.dmg`.

The README is the source of truth for end-user commands and deploy steps. Read it before answering "how do I…" questions.

## Layout

```
src/paper_manager/        Python package (CLI entry: paper_manager.cli:app)
  cli.py                  Typer commands — every `paper <cmd>` lives here
  app.py                  FastAPI app (paper serve)
  ingest.py               PDF → text → kind detect → Claude summary → embed → write
  fetch_url.py            arXiv / direct PDF / HTML article fetch
  pdf.py figures.py       PyMuPDF + pypdf/pdfminer extraction
  claude.py               Subprocess shell-out to local `claude` CLI (no API key)
  embed.py                Ollama HTTP client (mxbai-embed-large, 1024-d)
  db.py                   SQLite schema + migrations (papers, chunks, prefs, FTS5)
  cache.py                Rebuild SQLite from iCloud files
  storage.py              iCloud paths + paper_id (sha-derived) + metadata.json
  search.py recs.py       Vector + FTS search, Netflix-style recommendation rows
  discover.py             arXiv polling + ranking against library
  export_site.py          Static HTML export (academic /papers listing)
  templates/ static/      Jinja2 + CSS/JS for the web UI
  migrate/zotero.py       Bulk import a Zotero storage folder

macapp/                   SwiftUI app, SPM-built (Package.swift)
  Sources/PaperManagerApp/
    Models/               Paper, Prefs (Codable mirrors of metadata.json/prefs.json)
    Views/                RootView, Sidebar, PaperList, PaperDetail, AddSheet, …
    Services/             LibraryStore, IngestService, Config, CLIRunner
  build.sh                ./build.sh {release|debug|run|dmg}
  Resources/Info.plist    Bundle metadata, version

prompts/                  keshav-three-pass.md (paper) + non-paper prompt
site/                     Last local static export (gitignored)
config.toml(.example)     Per-machine config; gitignored
pyproject.toml uv.lock    uv-managed Python deps
```

## Data lives in iCloud, not the repo

```
~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/
├── library/<paper_id>/  paper.pdf, metadata.json, summary.md, text.txt, chunks.json, figures/
├── user/                prefs.json, history.jsonl
└── inbox/               drop PDFs here → paper sync-inbox

~/Library/Application Support/paper_manager/library.sqlite   (cache, rebuildable)
```

`paper_id` is derived from the SHA-256 of the PDF — same file ingested twice is a no-op. The SQLite cache is **disposable**; `paper rebuild-cache` recreates it from iCloud. Don't add migrations that assume DB is canonical.

## Key invariants

- **iCloud files are canonical**, SQLite is a cache. Any new persistent field must round-trip through `metadata.json` / `prefs.json`, not just the DB.
- **The macapp and Python app share on-disk format.** A schema change in one side must work for the other — check `macapp/Sources/PaperManagerApp/Models/` if you change `metadata.json` or `prefs.json`.
- **Claude is invoked via the local `claude` CLI**, not the API (`claude.py` shells out). No `ANTHROPIC_API_KEY` needed.
- **Embeddings are local-only via Ollama** at `http://localhost:11434` using `mxbai-embed-large` (1024-d).
- **Three kinds**: `paper` | `book` | `report`. Books/reports skip the Keshav three-pass prompt — see `ingest.py` around the `kind != "paper"` branch.

## Common dev workflows

```bash
uv sync && uv pip install -e .          # Python dev install
paper serve                              # web UI on :8765 (check `lsof -ti:8765` first)
paper rebuild-cache                      # after schema changes

cd macapp && ./build.sh run              # build + launch macOS app
cd macapp && ./build.sh dmg              # ship a release DMG
```

There is **no test suite**. Validate changes by ingesting a real PDF and exercising the affected surface.

## Positioning (from user memory)

This is the user's personal research document manager. Don't frame it as "Zotero-lite" or position the macapp against Zotero — see `.claude/agents/paper-manager-pm.md` (invoke via `paper-manager-pm` subagent_type) for PM-style scope decisions.

## Deploy

Static export publishes to `randomstorms.net/papers/` via a *separate* repo (`~/Archive/website/`) that Netlify watches. See README "Deploy to randomstorms.net/papers/" — prefer the two-step form over `paper publish` when the website repo has unrelated edits.
