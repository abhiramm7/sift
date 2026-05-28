# Paper Manager

A local web app for your paper library. PDFs live in iCloud, Claude writes summaries via the `claude` CLI, Ollama runs the embedder locally (`mxbai-embed-large`). SQLite is the local cache, rebuildable from iCloud. A static-site export publishes the academic listing to a public site (currently [randomstorms.net/papers/](https://randomstorms.net/papers/) via Netlify).

Summaries follow [S. Keshav's three-pass reading method](https://web.stanford.edu/class/ee384m/Handouts/HowtoReadPaper.pdf) for papers. Books and reports skip the three-pass framing and use a longer-form prompt instead.

There's also a **native macOS app** in [`macapp/`](macapp/) — a standalone SwiftUI catalog over the same iCloud folder. It does ingest, tagging, ratings, read/unread, and search natively; no Python required. The Python CLI here adds the LLM-driven extras (Keshav summaries, embeddings, recommendations, arXiv discovery). The two share the same on-disk format and coexist.

---

## For Claude / agents working in this repo

The fastest path to common tasks:

| You want to… | Do this |
|---|---|
| Add one PDF | `paper add /path/to/file.pdf --tags rl,llm` |
| Add an arXiv link / blog URL | `paper add-url https://arxiv.org/abs/1709.04875 --tags hydrology` |
| Drop PDFs into iCloud, then ingest the lot | Move files into `~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/inbox/`, then `paper sync-inbox` |
| Bulk-import a Zotero export | `paper migrate-zotero --root /path/to/zotero/storage` |
| Check what's in the library | `paper status` |
| Re-run summary on one paper | `paper resummarize <id>` (find id under `~/.../PaperManager/library/<id>/`) |
| Re-run summary on every paper | `paper resummarize --all` |
| Re-classify a paper as book / report | `paper kind <id> book` |
| Delete a paper | `paper delete <id>` |
| Start the local web UI | `paper serve` → [http://127.0.0.1:8765](http://127.0.0.1:8765) |
| Rebuild the SQLite cache from iCloud | `paper rebuild-cache` |
| Render the static site only (no push) | `paper export-site --out ./site` |
| **Publish to randomstorms.net** | See the [Deploy section](#deploy-to-randomstormsnetpapers) below |

The local server typically runs on port `8765`. Before starting it, check with `lsof -ti:8765` — if it's already up, just `open http://127.0.0.1:8765`.

---

## Setup

```bash
uv sync
uv pip install -e .

# Ollama: free, local, no rate limits
brew install ollama && brew services start ollama
ollama pull mxbai-embed-large

# Claude: uses your local `claude` CLI auth — no Anthropic API key needed.

paper init           # creates iCloud folders + local SQLite + config.toml
paper add <pdf>      # or paper migrate-zotero for bulk import
paper serve          # http://127.0.0.1:8765
```

---

## Adding papers — every method

Three ways, in order of convenience:

### 1. Web UI (drag-and-drop)

```bash
paper serve   # if not already running
```

Open [http://127.0.0.1:8765/library](http://127.0.0.1:8765/library) and drag PDFs onto the upload box, or click **Upload PDF(s)**. Tags are optional, comma-separated.

### 2. iCloud inbox

Drop PDFs anywhere into:

```
~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/inbox/
```

From any device that syncs iCloud. Then either:

- Click **"Scan iCloud inbox"** on the `/library` page, or
- Run `paper sync-inbox` from the terminal.

Successfully ingested PDFs are removed from `inbox/`.

### 3. CLI

```bash
# Single local PDF
paper add /path/to/paper.pdf --tags reinforcement-learning,llm

# Any URL — arXiv abstract page, arXiv id, direct PDF link, or HTML article
paper add-url https://arxiv.org/abs/1709.04875 --tags hydrology
paper add-url 2401.12345                                      # bare arxiv id works
paper add-url https://example.com/post --tags blog

# Bulk import every PDF in a Zotero storage folder
paper migrate-zotero --root ~/Zotero/storage --limit 50 --skip 0
```

What ingestion does for every paper:

1. Extracts text (pypdf → pdfminer fallback)
2. Detects kind — `paper` / `book` / `report` (heuristic: >80 pages → book; "report" in title → report)
3. Calls `claude` CLI with the appropriate prompt (`prompts/keshav-three-pass.md` for papers)
4. Embeds chunks via Ollama (`mxbai-embed-large`)
5. Extracts figures via PyMuPDF
6. Writes everything to `~/.../PaperManager/library/<paper_id>/` and the SQLite cache

---

## All commands

| Command | Purpose |
|---|---|
| `paper init` | Create iCloud folders, init SQLite, write `config.toml`. |
| `paper add <pdf> [--tags X,Y]` | Ingest one local PDF. |
| `paper add-url <url> [--tags X,Y]` | Ingest from a URL — arXiv link/id, direct PDF link, or any blog/article. |
| `paper sync-inbox` | Ingest every PDF currently sitting in `inbox/`. |
| `paper migrate-zotero [--root PATH] [--limit N] [--skip N]` | Bulk-import a Zotero storage folder. |
| `paper status` | Show counts, paths, API key presence. |
| `paper resummarize [<id>] [--all]` | Re-run the summary prompt on existing papers. |
| `paper delete <id>` | Remove a paper (PDF, summary, figures, embeddings). |
| `paper kind <id> <paper\|book\|report>` | Re-classify a paper. |
| `paper classify-existing` | Backfill `kind` on every paper via PyMuPDF page count. |
| `paper follow [add\|remove\|list] [category]` | Manage arXiv categories that `paper discover` pulls from. |
| `paper discover` | Fetch new arXiv papers in followed categories, rank against your library. |
| `paper rebuild-cache` | Drop SQLite and rebuild from iCloud. |
| `paper serve [--port 8765]` | Launch the local web app. |
| `paper export-site [--out ./site]` | Render the academic listing to a static folder (no commit, no push). |
| `paper publish [--out PATH] [--no-inbox] [--no-push] [-m MSG]` | Full pipeline: scan inbox → ingest → export → git commit + push. |

---

## Local web app

- `/` — Netflix-style home with hero card, "Explore by topic", and recommendation rows (Continue reading, Claude's picks, Because you liked, From your favorite tags, Recently added).
- `/library` — search + browse, drag-and-drop upload, "Scan iCloud inbox" button.
- `/paper/<id>` — structured summary, methods/datasets/claims, rating + flag controls.
- `/papers` — academic-style listing in randomstorms.net flavor: chronological, inline-expandable summaries, no chrome.
- `/manage` — table view with per-row kind dropdown, tag edit, rename, delete; pill filter by kind (paper / book / report).
- `/settings` — paths, model, key status, rebuild-cache button.

---

## Deploy to randomstorms.net/papers/

The public site is served by Netlify from the `abhiramm7/website` repo on `master`. The `papers/` subdirectory inside that repo is the static export from this project — Netlify auto-deploys on push.

**Two-step publish (recommended — keeps the diff isolated to `papers/`):**

```bash
# 1. Re-export the static site into the website repo's papers/ folder
paper export-site --out ~/Archive/website/papers

# 2. Commit & push from the website repo
cd ~/Archive/website
git status papers/               # review what changed
git add papers/
git commit -m "papers: refresh export"
git push origin master            # Netlify auto-deploys within ~1 min
```

**One-shot via `paper publish`:**

```bash
paper publish --out ~/Archive/website/papers
```

This scans the iCloud inbox, ingests anything new, exports the site, then runs `git add -A && git commit && git push` from `~/Archive/website/papers`. Note: `git add -A` adds **all** changes in the website repo, not just `papers/` — use the two-step form if you have unrelated edits in `~/Archive/website/`.

Flags: `--no-inbox` skips the inbox scan, `--no-push` builds without pushing, `-m "msg"` overrides the commit message.

---

## Storage layout

```
~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/
├── library/<paper_id>/
│   ├── paper.pdf
│   ├── metadata.json     # title, authors, year, doi, arxiv_id, kind, tags…
│   ├── summary.md        # Claude output, Keshav three-pass for papers
│   ├── text.txt          # extracted full text
│   ├── chunks.json       # embedded chunks
│   └── figures/          # extracted images
├── user/
│   ├── prefs.json        # ratings, flags
│   └── history.jsonl     # read history
└── inbox/                # drop PDFs here, then sync-inbox

~/Library/Application Support/paper_manager/library.sqlite   # cache, rebuildable
~/Archive/paper_manager/site/                                # last local export (gitignored)
~/Archive/website/papers/                                    # what Netlify serves
```

---

## Config

`config.toml` at the repo root:

```toml
[storage]
icloud_root = "/Users/pluto/Library/Mobile Documents/com~apple~CloudDocs/PaperManager"

[claude]
model = "claude-sonnet-4-6"

[embed]
model = "mxbai-embed-large"
```

Copy from `config.toml.example` and adjust paths. Gitignored — each machine has its own.

---

## Costs

- Claude: free, routed through your `claude` CLI subscription.
- Embeddings: free, fully local via Ollama (`mxbai-embed-large`, 1024-dim, no rate limits).
- Hosting: free, Netlify static deploy from a public GitHub repo.
