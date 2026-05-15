# Paper Manager

A local web app for your paper library. PDFs live in iCloud, Claude writes summaries via the `claude` CLI, Ollama runs the embedder locally (`mxbai-embed-large`). SQLite is the local cache, rebuildable from iCloud. There's a static-site export so you can publish your `Papers` page as a public site on GitHub Pages.

## Setup

```bash
uv sync
uv pip install -e .

# Ollama: free, local, no rate limits
brew install ollama && brew services start ollama
ollama pull mxbai-embed-large

# Claude: uses your local `claude` CLI auth — no Anthropic API key needed.

paper init           # creates iCloud folders + local SQLite
paper add <pdf>      # or paper migrate-zotero for bulk import
paper serve          # http://127.0.0.1:8765
```

## Commands

| Command | Purpose |
|---|---|
| `paper init` | Create iCloud folders, init SQLite, write `config.toml`. |
| `paper add <pdf> [--tags X,Y]` | Ingest one local PDF. |
| `paper add-url <url> [--tags X,Y]` | Ingest from a URL — arXiv link/id, direct PDF link, or any blog/article. |
| `paper sync-inbox` | Ingest every PDF currently sitting in `inbox/`. |
| `paper publish [--out PATH]` | Full pipeline: scan inbox → ingest → export static site → git commit + push. |
| `paper migrate-zotero [--root PATH] [--limit N] [--skip N]` | Bulk-import a Zotero storage folder. |
| `paper resummarize [<id>] [--all]` | Re-run the Keshav summary prompt on existing papers. |
| `paper status` | Show counts, paths, API key presence. |
| `paper rebuild-cache` | Drop SQLite and rebuild from iCloud. |
| `paper serve [--port 8765]` | Launch the local web app. |
| `paper export-site [--out ./site]` | Render `/papers` to a static folder without git push. |

## Local web app

- `/` — Netflix-style home with hero card, "Explore by topic", and recommendation rows (Continue reading, Claude's picks, Because you liked, From your favorite tags, Recently added).
- `/library` — search + browse, drag-and-drop upload, "Scan iCloud inbox" button.
- `/paper/<id>` — structured summary, methods/datasets/claims, rating + flag controls.
- `/papers` — academic-style listing in randomstorms.net flavor: chronological, inline-expandable summaries, no chrome.
- `/settings` — paths, model, key status, rebuild-cache button.

## The pipeline (laptop → iCloud → laptop → GitHub → public web)

Everything expensive — Claude calls, embeddings, recommendations — stays on the laptop. You feed it papers / blogs / arXiv URLs, the laptop processes them through the Keshav three-pass prompt, and pushes the rendered summaries to a public GitHub repo you can read from anywhere.

**Three ways to feed it papers:**

1. **Drag a PDF into iCloud inbox** — drop into `~/Library/.../PaperManager/inbox/` from any device. Next `paper publish` picks it up.
2. **Share an arXiv link or blog URL** — `paper add-url https://arxiv.org/abs/1709.04875` or `paper add-url https://example.com/great-blog-post`.
3. **Drop on the local web UI** — drag-and-drop on the library page.

**One-shot publish:**

```bash
# First-time setup of the public site repo
mkdir -p ~/Code/papers-site && cd ~/Code/papers-site
git init -b main
gh repo create papers-site --public --source . --remote origin --push
# enable GitHub Pages: Settings → Pages → branch=main, root /

# After that, on the laptop, the only command you need:
paper publish --out ~/Code/papers-site
# → scans iCloud inbox, ingests new PDFs, runs Keshav summary,
#   exports the academic /papers page to ~/Code/papers-site/,
#   git commit + push. Visible on github.io within a minute.
```

`site/index.html` is the listing; `site/paper/<id>.html` is one detail page per paper; `site/static/site.css` and `site/static/site.js` are referenced by both. **PDFs are not included** — only Keshav-style summaries + extracted metadata. Source URLs are preserved so a reader can click through to the original.

## Storage

- **iCloud** — `~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/`
  - `library/<paper_id>/` — `paper.pdf`, `metadata.json`, `summary.md`, `text.txt`, `chunks.json`
  - `user/prefs.json`, `user/history.jsonl`
  - `inbox/` — drop PDFs here, then click "Scan iCloud inbox" in the web UI.
- **Local cache** — `~/Library/Application Support/paper_manager/library.sqlite` (rebuildable).
- **Public site export** — `./site/` (committed to your public repo).

## Costs

- Claude: free, routed through your `claude` CLI subscription.
- Embeddings: free, fully local via Ollama (`mxbai-embed-large`, 1024-dim, no rate limits).
