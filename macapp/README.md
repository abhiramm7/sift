# PaperManager (macOS)

A lightweight catalog for research papers and books. Drop in PDFs, tag them,
rate them, mark them read. Everything is stored as plain files in a folder of
your choice — keep it in iCloud Drive and your library syncs across devices.

PaperManager opens PDFs in Preview (your system default), so it stays small
and out of your way. No login, no cloud service, no embedded reader.

## Install

1. Download `PaperManager-<version>.dmg` (built from this repo, or shared
   with you).
2. Open the DMG and drag `PaperManager.app` into `Applications`.
3. Right-click the app → **Open** → **Open**.
   (This build is signed ad-hoc, not notarized, so Gatekeeper warns on first
   launch. You only need to do the right-click trick once.)

## First-run setup

On first launch, the app asks where your library should live. The default is
inside iCloud Drive:

```
~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/
```

That folder will sync to every Apple device signed into the same iCloud
account. You can also point at any other folder (it just won't sync).

If you already have a `PaperManager/` folder from another machine, point the
app at it — your existing papers, tags, ratings, and read status all show up.

## Adding papers

- **Drag a PDF** onto the window. It's ingested in place.
- **⌘N** opens the Add sheet — choose a local PDF or paste an arXiv link/ID
  (e.g. `https://arxiv.org/abs/1706.03762` or `1706.03762`). The app fetches
  the PDF and stores it locally.
- Files dropped into `<library>/inbox/` from another device get picked up the
  next time you press **⌘R** (refresh).

## Organizing

- **Filters** (left sidebar): All / Unread / Starred, by kind (paper / book /
  report), or by tag.
- **Sort** (toolbar): by recency, title, or year. Or click column headers.
- **Search** (toolbar): matches title, authors, tags, venue.
- **Rate** (detail pane): 1–5 stars. Click the same star again to clear.
- **Read / Unread** (detail pane or right-click): toggles a flag per paper.
- **Star** (detail pane or right-click): pins to the *Starred* filter.

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

The file shape matches the Python `paper` CLI (a separate, optional tool that
adds LLM-generated summaries and embeddings). The two coexist — you can run
this app alone, or layer the CLI on top for power features.

## Build from source

```bash
cd macapp
./build.sh run          # builds release + opens the app
./build.sh debug        # faster compile, slower runtime, useful for editing
./build.sh dmg          # produces PaperManager-<version>.dmg next to build.sh
```

Requires Xcode (Swift 5.9+, macOS 14 SDK) installed. Pure SPM — no Xcode
project files.

## What it doesn't do yet

- Generate LLM summaries (deferred — handled by the Python `paper` CLI for now)
- Auto-tagging via LLM (planned)
- PDF annotations (deliberately — open in Preview for that)
- CloudKit / push sync (uses iCloud Drive, which means a few-second delay)

## File locations to know

| What | Where |
|---|---|
| Your library | wherever you pointed it on first launch |
| App preferences | `~/Library/Preferences/net.randomstorms.PaperManager.plist` |
| The app | `/Applications/PaperManager.app` |
