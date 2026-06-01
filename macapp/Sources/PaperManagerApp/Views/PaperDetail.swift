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
                    .font(.title2.weight(.semibold))
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
                    Label("\(y)", systemImage: "calendar")
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
            }
        }
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
                .padding(.top, 6)
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
                TextField("add tag…", text: $newTagDraft)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 80, maxWidth: 140)
                    .onSubmit { commitNewTag() }
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
                .overlay(Capsule().stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
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
                if let attr = try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .full)
                ) {
                    Text(attr)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
