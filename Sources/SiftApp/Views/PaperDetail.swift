import SwiftUI

struct PaperDetail: View {
    @EnvironmentObject var store: LibraryStore
    let paper: Paper

    @State private var summary: String?
    @State private var loadedID: String?
    @State private var showDeleteConfirm: Bool = false
    // Title editing
    @State private var editingTitle: Bool = false
    @State private var titleDraft: String = ""
    // User-tag entry
    @State private var newTagDraft: String = ""
    // Raw metadata disclosure (hidden by default)
    @State private var showRawMeta: Bool = false
    // New-folder sheet
    @State private var showNewFolderSheet: Bool = false
    @State private var newFolderDraft: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                actionRow
                ratingRow
                Divider()
                tagsRow
                metaGrid
                Divider()
                summaryBlock
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadSummaryIfNeeded)
        .onChange(of: paper.id) { _, _ in
            summary = nil
            loadedID = nil
            loadSummaryIfNeeded()
        }
        .onChange(of: paper.auto) { _, _ in
            // metadata.json was rewritten (likely by the tagger) — reload summary.md too.
            summary = store.loadSummary(paper)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if editingTitle {
                HStack(spacing: 6) {
                    TextField("Title", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .onSubmit { commitTitleEdit() }
                    Button("Save", action: commitTitleEdit)
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { editingTitle = false }
                        .keyboardShortcut(.cancelAction)
                }
            } else {
                Text(paper.title)
                    .font(.title3.weight(.semibold))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .onTapGesture(count: 2) { startTitleEdit() }
                    .help("Double-click to edit")
                    .contextMenu {
                        Button("Edit title…") { startTitleEdit() }
                    }
            }
            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 12) {
                if let y = paper.year {
                    Label(String(y), systemImage: "calendar")
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                if let v = paper.venue, !v.isEmpty {
                    Label(v, systemImage: "building.columns")
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                }
                Menu {
                    ForEach(PaperKind.allCases, id: \.self) { k in
                        Button {
                            store.setKind(k, for: paper.id)
                        } label: {
                            if k == paper.kind {
                                Label(k.label, systemImage: "checkmark")
                            } else {
                                Text(k.label)
                            }
                        }
                    }
                } label: {
                    Label(paper.kind.label, systemImage: paper.kind.symbol)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Change kind")
                folderMenu
            }
        }
    }

    /// Folder picker — sits next to Kind. Lists existing folders (with a
    /// checkmark on the current one), a "New folder…" entry, and "Use
    /// suggested" when a user override is active.
    @ViewBuilder
    private var folderMenu: some View {
        let effective = paper.effectiveFolder
        let hasUserOverride = (paper.user_folder?.isEmpty == false)
        let folders = store.allFolders.map { $0.folder }
        Menu {
            ForEach(folders, id: \.self) { name in
                Button {
                    store.setUserFolder(name, for: paper.id)
                } label: {
                    if effective?.caseInsensitiveCompare(name) == .orderedSame {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            if !folders.isEmpty { Divider() }
            Button("New folder…") {
                newFolderDraft = ""
                showNewFolderSheet = true
            }
            if hasUserOverride {
                Divider()
                Button("Use suggested") {
                    store.setUserFolder(nil, for: paper.id)
                }
                .help("Clear the manual override and use the LLM's suggestion (\(paper.auto?.folder ?? "none yet"))")
            }
        } label: {
            Label(effective ?? "No folder", systemImage: "folder")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(hasUserOverride
              ? "Folder (manually set). Suggested: \(paper.auto?.folder ?? "none yet")."
              : "Folder (auto-assigned). Pick to override.")
        .sheet(isPresented: $showNewFolderSheet) {
            newFolderSheet
        }
    }

    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New folder").font(.headline)
            TextField("Folder name", text: $newFolderDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { commitNewFolder() }
            HStack {
                Spacer()
                Button("Cancel") { showNewFolderSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: commitNewFolder)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    private func commitNewFolder() {
        let cleaned = newFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        store.setUserFolder(cleaned, for: paper.id)
        showNewFolderSheet = false
    }

    private func startTitleEdit() {
        titleDraft = paper.title
        editingTitle = true
    }

    private func commitTitleEdit() {
        let cleaned = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty, cleaned != paper.title {
            store.setTitle(cleaned, for: paper.id)
        }
        editingTitle = false
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                store.openInPreview(paper)
            } label: {
                Label("Open in Preview", systemImage: "doc.richtext")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button {
                store.revealInFinder(paper)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            ShareLink(item: store.config.pdfURL(paper.id)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share the PDF — AirDrop, Mail, Messages, Notes, etc.")

            if let arxiv = paper.arxiv_id, !arxiv.isEmpty,
               let url = URL(string: "https://arxiv.org/abs/\(arxiv)") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("arXiv", systemImage: "link")
                }
            }
            Spacer()
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Move this paper to the Trash (⌫)")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .confirmationDialog(
            "Move \"\(paper.title)\" to the Trash?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                store.deletePaper(paper.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The PDF and metadata move to the Trash. Reversible until you empty it.")
        }
    }

    private var ratingRow: some View {
        let prefs = store.prefs(for: paper.id)
        let currentRating = prefs.rating ?? 0
        return HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        // Toggle: clicking the current star clears the rating.
                        store.setRating(currentRating == i ? nil : i, for: paper.id)
                    } label: {
                        Image(systemName: i <= currentRating ? "star.fill" : "star")
                            .foregroundStyle(i <= currentRating ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rate \(i)")
                }
                if currentRating > 0 {
                    Button {
                        store.setRating(nil, for: paper.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear rating")
                }
            }
            .font(.title3)
            .padding(.trailing, 12)

            Toggle(isOn: Binding(
                get: { prefs.read },
                set: { store.setRead($0, for: paper.id) }
            )) {
                Label(prefs.read ? "Read" : "Unread",
                      systemImage: prefs.read ? "checkmark.circle.fill" : "circle")
            }
            .toggleStyle(.button)
            .help(prefs.read ? "Mark as unread" : "Mark as read")

            Toggle(isOn: Binding(
                get: { prefs.saved },
                set: { store.setStarred($0, for: paper.id) }
            )) {
                Label(prefs.saved ? "Saved" : "Save",
                      systemImage: prefs.saved ? "bookmark.fill" : "bookmark")
            }
            .toggleStyle(.button)
            .help(prefs.saved ? "Remove from Saved" : "Save for later")

            Spacer()
        }
    }

    private var tagsRow: some View {
        let userTags = paper.user_tags
        let topics = filterAutoTags(paper.auto?.topics ?? [], against: userTags)
        let apps = filterAutoTags(paper.auto?.application_areas ?? [], against: userTags)
        let methods = filterAutoTags(paper.auto?.methods ?? [], against: userTags)
        let isTagging = store.taggingInFlight.contains(paper.id)
        return VStack(alignment: .leading, spacing: 8) {
            // User tags row — always shown with the inline add field so the
            // user always has a path to add their own tag even on cold start.
            userTagsRow(userTags: userTags)
            if !topics.isEmpty {
                tagChipRow(label: "Topics", tags: topics, style: .auto)
            }
            if !apps.isEmpty {
                tagChipRow(label: "Applications", tags: apps, style: .auto)
            }
            if !methods.isEmpty {
                tagChipRow(label: "Methods", tags: methods, style: .auto)
            }
            HStack(spacing: 8) {
                if isTagging {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("tagging…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Button {
                            store.cancelTagging(for: paper.id)
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop tagging this paper")
                    }
                } else {
                    generateTagsButton
                }
                Spacer()
            }
        }
    }

    /// The user-tags row, with an inline text field for adding new tags and
    /// click-to-delete on existing chips.
    private func userTagsRow(userTags: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Tags")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
                .padding(.top, 3)
            FlowLayout(spacing: 6) {
                ForEach(userTags, id: \.self) { t in
                    Button {
                        store.removeUserTag(t, for: paper.id)
                    } label: {
                        HStack(spacing: 3) {
                            Text("#\(t)")
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Click to remove")
                }
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("add tag", text: $newTagDraft)
                        .textFieldStyle(.plain)
                        .frame(minWidth: 60, maxWidth: 120)
                        .onSubmit { commitNewTag() }
                }
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(
                    Capsule().stroke(
                        Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [3]))
                )
            }
        }
    }

    private func commitNewTag() {
        let cleaned = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        // Accept comma-separated to add several at once.
        let parts = cleaned.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }.filter { !$0.isEmpty }
        for t in parts {
            store.addUserTag(t, for: paper.id)
        }
        newTagDraft = ""
    }

    private enum ChipStyle { case user, auto }

    private func tagChipRow(label: String, tags: [String], style: ChipStyle) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
                .padding(.top, 3)
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    chip(t, style: style)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ text: String, style: ChipStyle) -> some View {
        switch style {
        case .user:
            Text("#\(text)")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                .foregroundStyle(.primary)
        case .auto:
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
        }
    }

    /// Drop auto-tags that duplicate (case-insensitive) a user tag.
    private func filterAutoTags(_ tags: [String], against userTags: [String]) -> [String] {
        let userLower = Set(userTags.map { $0.lowercased() })
        return tags.filter { !userLower.contains($0.lowercased()) }
    }

    private var generateTagsButton: some View {
        let hasAuto = !(paper.auto?.tags?.isEmpty ?? true)
        return Button {
            // Manual regenerate reads the whole paper (Claude) / provider cap (Ollama).
            store.generateTagsInBackground(for: paper.id, force: true, mode: .full)
        } label: {
            Label(hasAuto ? "Regenerate" : "Generate tags", systemImage: "sparkles")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!store.llmProvider.isAvailable)
        .help(store.llmProvider.isAvailable
              ? "Run \(store.llmProvider.label) over the full paper to regenerate tags, title, authors, summary"
              : "No LLM detected. Install Claude Code or run Ollama with a chat model.")
    }

    private var metaGrid: some View {
        DisclosureGroup(isExpanded: $showRawMeta) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                metaRow("ID", paper.id)
                if let p = paper.pages { metaRow("Pages", String(p)) }
                metaRow("Source", paper.source)
                if !paper.added_at.isEmpty { metaRow("Added", Self.formatAdded(paper.added_at)) }
                if !paper.sha256.isEmpty { metaRow("SHA-256", String(paper.sha256.prefix(12)) + "…") }
            }
            .font(.callout)
            .padding(.top, 4)
        } label: {
            Text("Details")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private static func formatAdded(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .none
        return out.string(from: d)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    private func autoBlock(_ title: String, items: [String]?, bulleted: Bool = false) -> some View {
        Group {
            if let items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if bulleted {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(item).textSelection(.enabled)
                            }
                            .font(.callout)
                        }
                    } else {
                        Text(items.joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func codeLinks(_ links: [CodeLink]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Code").font(.subheadline.weight(.semibold))
            ForEach(links, id: \.url) { link in
                if let url = URL(string: link.url) {
                    Link(link.url, destination: url)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryBlock: some View {
        let isTagging = store.taggingInFlight.contains(paper.id)
        if let text = summary, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Summary").font(.headline)
                renderedSummary(text)
            }
        } else if isTagging {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Generating summary…").font(.caption).foregroundStyle(.secondary)
                Button {
                    store.cancelTagging(for: paper.id)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Stop tagging this paper")
            }
        }
        // else: nothing — empty summary block was visual noise (PM call).
    }

    /// Render an LLM-generated Markdown summary with section structure.
    /// Splits on `## ` headings and shows each as a bold subheading + body.
    /// Robust to LLM output that doesn't put a blank line between heading and
    /// body (the "no space after TL;DR" bug).
    @ViewBuilder
    private func renderedSummary(_ source: String) -> some View {
        let sections = Self.parseSummarySections(source)
        if sections.count <= 1 {
            // No headings — render the whole thing as one inline-markdown blob.
            renderedInline(source)
                .font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, sec in
                    VStack(alignment: .leading, spacing: 4) {
                        if !sec.heading.isEmpty {
                            Text(sec.heading)
                                .font(.subheadline.weight(.semibold))
                        }
                        if !sec.body.isEmpty {
                            renderedInline(sec.body)
                                .font(.callout)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderedInline(_ text: String) -> some View {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct SummarySection {
        var heading: String
        var body: String
    }

    /// Split a Markdown summary into sections at `##` / `#` headings.
    /// Handles the "TL;DRThis paper..." case where the LLM forgot to put a
    /// newline between heading and body by detecting `## Heading<no-space>body`.
    private static func parseSummarySections(_ source: String) -> [SummarySection] {
        // Normalize Windows-style line endings and ensure heading lines are
        // separated from their bodies. The LLM sometimes writes
        // "## TL;DR\nfoo" — fine. Sometimes writes "## TL;DRfoo" — needs a
        // break. We can't reliably detect the latter without the heading
        // being a known label, so we special-case our two prompt-defined ones.
        var normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        for label in ["TL;DR", "Key contributions", "Methods", "Datasets", "Claims"] {
            // Insert a newline if the LLM ran the body right into the label.
            normalized = normalized.replacingOccurrences(
                of: "## \(label)",
                with: "##__SPLIT__\(label)\n"
            )
        }
        normalized = normalized.replacingOccurrences(of: "##__SPLIT__", with: "## ")

        var sections: [SummarySection] = []
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var current = SummarySection(heading: "", body: "")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                // Push previous section if non-empty
                if !current.heading.isEmpty || !current.body.isEmpty {
                    current.body = current.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    sections.append(current)
                }
                current = SummarySection(heading: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces), body: "")
            } else if trimmed.hasPrefix("# ") {
                if !current.heading.isEmpty || !current.body.isEmpty {
                    current.body = current.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    sections.append(current)
                }
                current = SummarySection(heading: String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces), body: "")
            } else {
                if !current.body.isEmpty { current.body += "\n" }
                current.body += line
            }
        }
        // Final flush
        if !current.heading.isEmpty || !current.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            current.body = current.body.trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(current)
        }
        return sections
    }

    private func loadSummaryIfNeeded() {
        guard loadedID != paper.id else { return }
        loadedID = paper.id
        summary = store.loadSummary(paper)
    }
}

/// Minimal flow layout for chip tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
