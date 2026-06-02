# Sift

Fast, native macOS app to **collect → tag → rate → recall** papers, books, and
reports. No account, no subscription, no clutter. Your library is plain files in
a folder you choose; keep it in iCloud Drive and it syncs across your Macs. PDFs
open in Preview.

**[Download](https://github.com/abhiramm7/sift/releases)** ·
**[Project page](https://abhiramm7.github.io/sift/)**

## Why

Zotero, Mendeley, and Papers try to be everything and got heavy. Most of the time
the job is simpler: keep track of what you read so you can find it again. Sift
does that loop and little else. It's a catalog, not a citation manager — if you
need BibTeX and DOI lookups, keep your current tool.

## Sync & cost

Sift has no sync server. It writes plain files, and if the library folder lives
in iCloud Drive (the default), macOS syncs it across your Macs. Your papers use
the iCloud storage you already pay for instead of a separate fee: Zotero charges
past its 300 MB free tier ($20/$60/$120 a year for 2/6/unlimited GB), while
iCloud's free 5 GB alone is about 16× that. Caveats: iCloud Drive sync has a
few-second delay (not push), works only across Apple devices (Sift is macOS-only),
and a local-only folder works too.

## Install

1. Download `Sift-<version>.dmg` from [Releases](https://github.com/abhiramm7/sift/releases).
2. Drag `Sift.app` into `Applications`.
3. Right-click → **Open** → **Open** (ad-hoc signed, so Gatekeeper warns once).

On first launch you pick where the library lives. Default:
`~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/` (named
`PaperManager/` for legacy round-tripping — any folder works). Point it at an
existing library and your papers, tags, and ratings show up.

## Using it

- **Add:** drag a PDF onto the window, **⌘N** to add a file or arXiv link/ID, or
  drop into `<library>/inbox/` and press **⌘R**.
- **Organize:** sidebar filters (All / Unread / Saved / Rated 4+, by kind, by
  tag); sort and search the list; rate 1–5; toggle read/saved; edit title, kind,
  and tags inline; **⌫** deletes to Trash.
- **Auto-tag (optional):** with Claude Code or Ollama installed, Sift fills
  Topics/Applications/Methods tags, fixes bad titles/authors, and writes a short
  summary at ingest. Pick the provider and model in Settings. Works fine without
  either.

## Build

```bash
./build.sh run     # build + launch
./build.sh debug   # faster compile
./build.sh dmg     # produces Sift-<version>.dmg
```

Requires Xcode (Swift 5.9+, macOS 14 SDK). Pure SPM, no Xcode project.

## On-disk layout

```
<library>/
├── library/<paper_id>/   paper.pdf, metadata.json
├── inbox/                drop PDFs here to ingest later
├── user/prefs.json       ratings, read/starred flags
└── tags.json             tag vocabulary
```

`paper_id` is the PDF's SHA-256, so re-ingesting a file is a no-op. The files on
disk are the source of truth; there's no separate database.

## Not yet / out of scope

No embedded PDF reader or annotations (use Preview), no citation export, no
CloudKit push sync. A Python `paper` CLI (LLM summaries, semantic search,
static-site export to randomstorms.net/papers/) lived here until 2026-06-01;
recoverable from git history.

## License

[GNU GPLv3](LICENSE). Copyright (C) 2026 Abhiram Mullapudi.
