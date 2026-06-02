# Sift

**Sift** is a fast, native macOS app for engineers and researchers who want to
**collect → tag → rate → recall** papers, books, and reports — without accounts,
subscriptions, or the complexity of Zotero or Mendeley.

No accounts. No server. No recurring fee. Everything lives as plain files in a
folder you control — keep it in iCloud Drive and your library syncs across
devices. PDFs open in Preview (your system default), so the app stays small and
out of your way.

The app lives in [`macapp/`](macapp/). See [`macapp/README.md`](macapp/README.md)
for the full install guide, keyboard shortcuts, organizing features, and the
optional LLM auto-tagging setup.

---

## Install

1. Download `Sift-<version>.dmg` from [Releases](https://github.com/abhiramm7/sift/releases).
2. Open the DMG, drag `Sift.app` into `Applications`.
3. Right-click → **Open** → **Open** (the build is signed ad-hoc, not notarized,
   so Gatekeeper warns on first launch — you only need the right-click once).

On first launch the app asks where to keep your library. The default is inside
iCloud Drive so it syncs across your Apple devices; you can point it at any
folder.

---

## What it does

- **Ingest** — drag a PDF onto the window, press **⌘N** to paste an arXiv
  link/ID, or drop files into `<library>/inbox/` and refresh.
- **Organize** — filters (All / Unread / Saved / Rated 4+, by kind, by tag),
  sort, and full-text-ish search over title / authors / tags / venue.
- **Annotate** — rate 1–5, toggle read/unread, save/bookmark, edit title / kind
  / tags inline, delete (to Trash).
- **Auto-tag (optional)** — if you have **Claude Code** or **Ollama** installed
  locally, Sift fills in topics / applications / methods plus a short summary at
  ingest time. Fully optional; ingest works without either.

---

## Build from source

```bash
cd macapp
./build.sh run          # build release + launch
./build.sh debug        # faster compile, slower runtime
./build.sh dmg          # produce Sift-<version>.dmg
```

Requires Xcode (Swift 5.9+, macOS 14 SDK). Pure SPM — no Xcode project files.

---

## Storage layout

Everything is plain files in the library folder you choose (default in iCloud
Drive):

```
<library>/
├── library/<paper_id>/
│   ├── paper.pdf
│   └── metadata.json     # title, authors, year, tags, kind, sha256…
├── inbox/                # drop PDFs here to ingest later
├── user/
│   └── prefs.json        # ratings, read flags, starred flags
└── tags.json             # library-wide tag vocabulary
```

`paper_id` is the SHA-256 of the PDF, so ingesting the same file twice is a
no-op. The default folder is named `PaperManager/` for historical reasons (so
existing libraries round-trip) — the name on disk doesn't matter; Sift uses
whichever folder you point it at.

---

## Not yet / out of scope

- Embedded PDF reader & annotations (deliberately — open in Preview for that).
- Citation export (BibTeX / RIS / DOI). Possible future optional add-on.
- CloudKit / push sync (uses iCloud Drive, so a few-second delay).
- Public static-site export to randomstorms.net/papers/. A Python `paper` CLI
  used to live in this repo and handled LLM summaries, semantic search, arXiv
  discovery, and the public-site export; it was removed on 2026-06-01. The
  public-site publishing may return later as a separate tool.
