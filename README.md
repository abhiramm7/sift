# Sift

**Sift** is a fast, native macOS app for engineers and researchers who want to
**collect → tag → rate → recall** papers, books, and reports, without the weight
of Zotero or Mendeley.

There's no account to make and nothing to subscribe to. Your papers live as plain
files in a folder you choose; keep that folder in iCloud Drive and your library
syncs across your Macs. PDFs open in Preview, your system default, so the app
stays small and out of your way.

**[Download Sift →](https://github.com/abhiramm7/sift/releases)** ·
**[Project page](https://abhiramm7.github.io/sift/)**

---

## Why this app should exist

Reference managers got heavy. Zotero, Mendeley, and Papers each try to be a
database, a PDF reader, a citation engine, a sync service, and a login all at
once, and they've gotten slow and cluttered in the process. More of them want a
subscription every year. The job most of us actually have is smaller than that:
keep track of what I read so I can find it again.

Day to day I don't need a citation manager. I need to grab a paper the moment I
find it, tag it so it turns up later, rate it so the good ones rise, and dig it
back out months later when it suddenly matters. That loop is what Sift is built
around, and it tries hard not to do much else.

A few things follow from that. Your library is just files: each paper is a PDF
and a small JSON file in a folder you pick, with no proprietary database and
nothing to export your way out of later. You can open it in Finder, back it up,
or grep it. It's a native Mac app, so it starts fast and stays out of the way,
and it hands PDFs to Preview instead of shipping a worse reader of its own.
There's no login and no telemetry, so you download it once and it stays a tool
rather than a service. And if you happen to have Claude Code or Ollama installed,
Sift will use them to tag and summarize papers locally; if you don't, the rest
works exactly the same.

So: a catalog, not a citation manager. If you need BibTeX and DOI lookups, keep
the tool you already have. But if your real problem is that you read papers and
then lose them, this is built for that.

---

## Sync is just iCloud Drive

Sift keeps your whole library in one folder. Put that folder in iCloud Drive
(it's there by default) and macOS keeps every paper, tag, and rating in sync
across your Macs. Sift has no sync server of its own and no account to set up. It
writes plain files, and iCloud moves them around the way it already does for
everything else on your Mac.

This is also where it saves you money. Zotero gives you 300 MB of file storage
free and then charges for more: roughly $20 a year for 2 GB, $60 for 6 GB, or
$120 for unlimited. A folder of PDFs passes 300 MB quickly. Sift doesn't run a
storage service at all, so your papers sit in the iCloud storage you already pay
for. The free 5 GB tier is already about sixteen times Zotero's free limit, and
if you pay for iCloud+ for photos and backups, your library just rides along on
it. If you're already paying for cloud storage, there's little reason to pay a
second time for your reference manager's version of it.

A few honest limits, so you know what you're getting:

- It's iCloud Drive file sync, not instant push. Changes take a few seconds to a
  few minutes to show up on another Mac, like any file in iCloud Drive.
- It syncs between Apple devices. Sift only runs on macOS, though the files also
  show up in the Files app on an iPhone or iPad.
- The files are small. A paper is usually 1 to 5 MB, so even a big library is a
  few hundred MB.
- Local-only works too. Pick a folder outside iCloud Drive on first launch and
  everything behaves the same, it just stays on that Mac.

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

## License

Sift is free software under the **GNU General Public License v3.0**. You can use,
study, share, and change it; if you distribute a modified version, it has to stay
under the GPL so everyone downstream keeps the same freedoms. Full text in
[`LICENSE`](LICENSE).

Copyright (C) 2026 Abhiram Mullapudi.
