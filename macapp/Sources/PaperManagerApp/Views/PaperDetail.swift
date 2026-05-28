import SwiftUI

struct PaperDetail: View {
    @EnvironmentObject var store: LibraryStore
    let paper: Paper

    @State private var summary: String?
    @State private var loadedID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                actionRow
                ratingRow
                Divider()
                tagsRow
                metaGrid
                if let auto = paper.auto {
                    autoBlock("Methods", items: auto.methods)
                    autoBlock("Datasets", items: auto.datasets)
                    autoBlock("Key terms", items: auto.key_terms)
                    autoBlock("Claims", items: auto.claims, bulleted: true)
                    if let links = auto.code_links, !links.isEmpty {
                        codeLinks(links)
                    }
                }
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(paper.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
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
                Label(paper.kind.label, systemImage: paper.kind.symbol)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
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
            if let doi = paper.doi, !doi.isEmpty,
               let url = URL(string: "https://doi.org/\(doi)") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("DOI", systemImage: "link")
                }
            }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
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

            Divider().frame(height: 20)

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
                Label(prefs.saved ? "Starred" : "Star",
                      systemImage: prefs.saved ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .help(prefs.saved ? "Unstar" : "Star")

            Spacer()
        }
    }

    private var tagsRow: some View {
        let tags = paper.allTags
        return Group {
            if tags.isEmpty {
                Text("No tags")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { t in
                        Text("#\(t)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var metaGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            metaRow("ID", paper.id)
            if let p = paper.pages { metaRow("Pages", String(p)) }
            metaRow("Source", paper.source)
            if !paper.added_at.isEmpty { metaRow("Added", paper.added_at) }
            if !paper.sha256.isEmpty { metaRow("SHA-256", String(paper.sha256.prefix(16)) + "…") }
        }
        .font(.callout)
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

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary").font(.headline)
            if let text = summary, !text.isEmpty {
                if let attr = try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
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
            } else {
                Text("No summary yet. Run `paper resummarize \(paper.id)` to generate one.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
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
