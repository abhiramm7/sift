# Sift (macOS)

A fast, native alternative to clunky paper-management tools (Zotero, Mendeley,
Papers/Readcube) — built for engineers and researchers who want to **collect,
tag, rate, and recall** the papers they read. Drop in PDFs, sift through them.
Everything is stored as plain files in a folder of your choice — keep it in
iCloud Drive and your library syncs across devices.

Sift opens PDFs in Preview (your system default), so it stays small and out of
your way. No login, no cloud service, no embedded reader, no recurring fee.

## Install

1. Download `Sift-<version>.dmg` (built from this repo, or shared with you).
2. Open the DMG and drag `Sift.app` into `Applications`.
3. Right-click the app → **Open** → **Open**.
   (This build is signed ad-hoc, not notarized, so Gatekeeper warns on first
   launch. You only need to do the right-click trick once.)

## First-run setup

On first launch, the app asks where your library should live. The default is
inside iCloud Drive:

```
~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/
```

(The default folder is still named `PaperManager/` — that's the on-disk
folder name, not the app name. Sift will happily use any folder you point
it at; the name on disk doesn't matter.)

That folder will sync to every Apple device signed into the same iCloud
account. You can also point at any other folder (it just won't sync).

If you already have a library folder from another machine, point the app at
it — your existing papers, tags, ratings, and read status all show up.

## Adding papers

- **Drag a PDF** onto the window. It's ingested in place.
- **⌘N** opens the Add sheet — choose a local PDF or paste an arXiv link/ID
  (e.g. `https://arxiv.org/abs/1706.03762` or `1706.03762`). The app fetches
  the PDF and stores it locally.
- Files dropped into `<library>/inbox/` from another device get picked up the
  next time you press **⌘R** (refresh).

## Organizing

- **Filters** (left sidebar): All / Unread / Saved / Rated 4+, by kind (paper /
  book / report), or by tag. The tag list shows the top 40 by default; click
  *Show all* for the full list with an inline search box.
- **Sort** (toolbar): by recency, title, year, or rating. Or click column headers.
- **Columns** (paper list): bookmark, read-state dot, title, authors,
  ★ rating, year, added date, kind.
- **Search** (toolbar): matches title, authors, tags, venue.
- **Rate** (detail pane): 1–5 stars. Click the same star again to clear.
- **Read / Unread** (detail pane or right-click): toggles a flag per paper.
- **Save** (detail pane or right-click): bookmarks the paper to the *Saved* filter.
- **Edit title / kind** (detail pane): double-click the title to edit;
  click the kind menu to change between paper / book / report.
- **Edit user tags** (detail pane): type into the *Tags* row to add (commas
  split multiple tags), click a chip's ✕ to remove.
- **Delete** (detail pane, right-click, or **⌫**): moves the paper to Trash.
  Reversible from Finder until you empty the Trash.

## Auto-tagging (optional)

If you have **Claude Code** or **Ollama** installed locally, the app uses them
to fill in topical metadata at ingest time — fully optional, ingest works
fine without either.

- **Tags by category.** Each paper gets three chip rows in the detail pane:
  **Topics** (subject areas), **Applications** (real-world domains), and
  **Methods** (techniques used). All categories are searchable and surface in
  the sidebar tag list.
- **Title & author cleanup.** If PDFKit gave you a bogus title
  (`1706.03762v7`, `Untitled`, a filename) or "Microsoft Word" as the author,
  the LLM proposes a replacement from the document text. Real titles you've
  edited are never touched.
- **Summary.** A short Markdown summary — TL;DR + key contributions — written
  to `<library>/library/<id>/summary.md` and shown in the detail pane.
- **Tag all** sparkle button in the toolbar processes any paper missing
  tags / a clean title / authors / summary. Runs 3 concurrently. Red stop
  button cancels mid-batch and kills the in-flight LLM processes.

**Configure** in Settings:

- **Use:** Auto (Claude preferred), Claude only, Ollama only, or Off.
- **Claude model:** `default` / `haiku` / `sonnet` / `opus`.
- **Ollama model:** any locally-installed chat model. Practical floor ~3B
  parameters — anything smaller can't reliably emit the structured schema.
  `qwen3.5:4b-mlx` is the proven sweet spot on Apple Silicon (~10s/paper).

Auto-on-ingest reads the first 3 pages of each PDF (fast, cheap). The
**Regenerate** button in the detail pane re-runs against the whole paper.

## On-disk layout

```
<library>/
├── library/<paper_id>/
│   ├── paper.pdf            the PDF
│   └── metadata.json        title, authors, year, tags, kind, sha256…
├── inbox/                   drop PDFs here to ingest later
└── user/
    └── prefs.json           ratings, read flags, starred flags
```

The format is plain JSON + files on disk, so it stays easy to inspect, back up,
and script against.

## Build from source

```bash
cd macapp
./build.sh run          # builds release + opens the app
./build.sh debug        # faster compile, slower runtime, useful for editing
./build.sh dmg          # produces Sift-<version>.dmg next to build.sh
```

Requires Xcode (Swift 5.9+, macOS 14 SDK) installed. Pure SPM — no Xcode
project files.

## What it doesn't do yet

- Citation export (BibTeX / RIS / DOI lookups). Out of current scope — could
  arrive later as an optional add-on; not a built-in.
- PDF annotations (deliberately — open in Preview for that).
- CloudKit / push sync (uses iCloud Drive, which means a few-second delay).

## File locations to know

| What | Where |
|---|---|
| Your library | wherever you pointed it on first launch |
| App preferences | `~/Library/Preferences/net.randomstorms.Sift.plist` |
| The app | `/Applications/Sift.app` |
