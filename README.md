# Sift

**Sift** is a fast, native macOS app for engineers and researchers who want to
**collect → tag → rate → recall** papers, books, and reports — without accounts,
subscriptions, or the complexity of Zotero or Mendeley.

No accounts. No server. No recurring fee. Everything lives as plain files in a
folder you control — keep it in iCloud Drive and your library syncs across
devices. PDFs open in Preview (your system default), so the app stays small and
out of your way.

**[Download Sift →](https://github.com/abhiramm7/sift/releases)** ·
**[Project page](https://abhiramm7.github.io/sift/)**

---

## Why this app should exist

Reference managers got heavy. Zotero, Mendeley, and Papers/ReadCube each want to
be a database, a PDF reader, a citation engine, a sync service, and an account
you log into — and they're slow, cluttered, and increasingly subscription-bound
for what is, at heart, a simple job: *keep track of the things I read so I can
find them again.*

Most working researchers and engineers don't need a citation manager day to day.
They need to **collect** a paper the moment they find it, **tag** it so it's
findable, **rate** it so the good stuff floats up, and **recall** it months later
when it's suddenly relevant. That's the whole loop. Sift does exactly that and
nothing it doesn't have to:

- **It's yours, as plain files.** Every paper is a PDF plus a small JSON file in
  a folder you pick. No proprietary database, no export ritual, no lock-in. Open
  it in Finder, back it up, grep it, sync it through iCloud — it's just files.
- **It's fast and native.** A SwiftUI Mac app that launches instantly and gets
  out of the way. It opens PDFs in Preview instead of shipping a worse reader.
- **It respects your attention.** No login, no cloud account, no upsell, no
  telemetry. One-time download, then it's a tool, not a service.
- **It's optional-smart.** If you have Claude Code or Ollama installed, Sift can
  auto-tag and summarize locally — but it works completely without them. The
  intelligence is a convenience, never a dependency.

Sift is a catalog, not a citation manager. If you need BibTeX export and DOI
lookups, keep your citation tool. If what you actually do all day is *read papers
and lose track of them*, this is for that.

---

## Install

1. Download `Sift-<version>.dmg` from [Releases](https://github.com/abhiramm7/sift/releases).
2. Open the DMG and drag `Sift.app` into `Applications`.
3. Right-click the app → **Open** → **Open**.
   (This build is signed ad-hoc, not notarized, so Gatekeeper warns on first
   launch. You only need the right-click trick once.)

## First-run setup

On first launch, the app asks where your library should live. The default is
inside iCloud Drive:

```
~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager/
```

(The default folder is named `PaperManager/` for historical reasons — that's the
on-disk folder name, not the app name. Sift will happily use any folder you point
it at; the name on disk doesn't matter.)

That folder syncs to every Apple device signed into the same iCloud account. You
can also point at any other folder (it just won't sync). If you already have a
library folder from another machine, point the app at it — your papers, tags,
ratings, and read status all show up.

## Adding papers

- **Drag a PDF** onto the window. It's ingested in place.
- **⌘N** opens the Add sheet — choose a local PDF or paste an arXiv link/ID
  (e.g. `https://arxiv.org/abs/1706.03762` or `1706.03762`). The app fetches the
  PDF and stores it locally.
- Files dropped into `<library>/inbox/` from another device get picked up the
  next time you press **⌘R** (refresh).

## Organizing

- **Filters** (left sidebar): All / Unread / Saved / Rated 4+, by kind (paper /
  book / report), or by tag.
- **Sort** (toolbar): by recency, title, year, or rating — or click column headers.
- **Search** (toolbar): matches title, authors, tags, venue.
- **Rate** (detail pane): 1–5 stars; click the same star again to clear.
- **Read / Unread** and **Save** (detail pane or right-click).
- **Edit title / kind / tags** (detail pane): double-click the title to edit;
  type into the *Tags* row to add (commas split multiple), click a chip's ✕ to remove.
- **Delete** (detail pane, right-click, or **⌫**): moves the paper to Trash,
  reversible from Finder until you empty it.

## Auto-tagging (optional)

If you have **Claude Code** or **Ollama** installed locally, the app uses them to
fill in topical metadata at ingest time — fully optional, ingest works fine
without either.

- **Tags by category.** Each paper gets three chip rows: **Topics**,
  **Applications**, and **Methods** — all searchable and surfaced in the sidebar.
- **Title & author cleanup.** If PDFKit produced a bogus title or author, the LLM
  proposes a replacement from the document text. Titles you've edited are never touched.
- **Summary.** A short Markdown summary written to `<library>/library/<id>/summary.md`.
- **Tag all** (toolbar sparkle): processes any paper missing tags / clean title /
  authors / summary, 3 concurrently. The red stop button cancels mid-batch.

Configure under Settings: provider (Auto / Claude only / Ollama only / Off),
Claude model (`default` / `haiku` / `sonnet` / `opus`), and Ollama model
(any locally-installed chat model; `qwen3.5:4b-mlx` is the sweet spot on Apple Silicon).

## Build from source

```bash
./build.sh run          # builds release + opens the app
./build.sh debug        # faster compile, slower runtime, useful while editing
./build.sh dmg          # produces Sift-<version>.dmg
```

Requires Xcode (Swift 5.9+, macOS 14 SDK). Pure SPM — no Xcode project files.

## On-disk layout

```
<library>/
├── library/<paper_id>/
│   ├── paper.pdf            the PDF
│   └── metadata.json        title, authors, year, tags, kind, sha256…
├── inbox/                   drop PDFs here to ingest later
├── user/
│   └── prefs.json           ratings, read flags, starred flags
└── tags.json                library-wide tag vocabulary
```

`paper_id` is the SHA-256 of the PDF, so ingesting the same file twice is a
no-op. The files on disk are the source of truth — there's no separate database.

## Not yet / out of scope

- Embedded PDF reader & annotations (deliberately — open in Preview for that).
- Citation export (BibTeX / RIS / DOI). Possible future optional add-on.
- CloudKit / push sync (uses iCloud Drive, so a few-second delay).
- Public static-site export to randomstorms.net/papers/. A Python `paper` CLI
  used to live in this repo and handled LLM summaries, semantic search, arXiv
  discovery, and the public-site export; it was removed on 2026-06-01 and is
  recoverable from git history. Public-site publishing may return later as a
  separate tool.

## File locations to know

| What | Where |
|---|---|
| Your library | wherever you pointed it on first launch |
| App preferences | `~/Library/Preferences/net.randomstorms.Sift.plist` |
| The app | `/Applications/Sift.app` |
