import SwiftUI

struct PaperList: View {
    @EnvironmentObject var store: LibraryStore
    let papers: [Paper]
    @Binding var selectedID: String?
    @Binding var searchText: String
    @Binding var sortOrder: [KeyPathComparator<Paper>]
    @State private var pendingDeleteID: String?

    var body: some View {
        Table(of: Paper.self, selection: $selectedID, sortOrder: $sortOrder) {
            TableColumn("") { p in
                Image(systemName: store.prefs(for: p.id).saved ? "bookmark.fill" : "")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
            }
            .width(20)

            TableColumn("Title", value: \Paper.titleSort) { p in
                Text(p.title)
                    .font(.body)
                    .lineLimit(2)
            }

            TableColumn("Authors") { p in
                Text(p.authorsShort).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 100, ideal: 160)

            TableColumn("Year", value: \Paper.yearSort) { p in
                Text(p.year.map(String.init) ?? "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 40, ideal: 50, max: 70)

            TableColumn("Added", value: \Paper.addedSort) { p in
                Text(Self.shortDate(p.addedDate))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 110)

            TableColumn("Kind") { p in
                Label(p.kind.label, systemImage: p.kind.symbol)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .help(p.kind.label)
            }
            .width(min: 32, ideal: 36, max: 50)
        } rows: {
            ForEach(sorted) { p in
                TableRow(p)
                    .contextMenu {
                        rowMenu(for: p)
                    }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search title, authors, tags")
        .overlay {
            if papers.isEmpty {
                ContentUnavailableView(
                    "No papers",
                    systemImage: "tray",
                    description: Text(emptyMessage)
                )
            }
        }
        .onDeleteCommand {
            if let id = selectedID { pendingDeleteID = id }
        }
        .alert(
            "Move paper to Trash?",
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            presenting: pendingDeleteID
        ) { id in
            Button("Move to Trash", role: .destructive) {
                let nextSelection = neighbor(of: id)
                store.deletePaper(id)
                selectedID = nextSelection
            }
            Button("Cancel", role: .cancel) {}
        } message: { id in
            if let p = store.papers.first(where: { $0.id == id }) {
                Text("\"\(p.title)\" will be moved to the Trash. The PDF and metadata are reversible from the Finder until you empty the Trash.")
            } else {
                Text("The paper will be moved to the Trash.")
            }
        }
    }

    /// Pick the next selection target after deleting `id`: prefer the row below,
    /// fall back to the one above, then nil.
    private func neighbor(of id: String) -> String? {
        guard let i = sorted.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < sorted.count { return sorted[i + 1].id }
        if i - 1 >= 0 { return sorted[i - 1].id }
        return nil
    }

    private var sorted: [Paper] {
        papers.sorted(using: sortOrder)
    }

    private var emptyMessage: String {
        if store.papers.isEmpty {
            return "Drop a PDF onto the window or press ⌘N to add one. Or run `paper add` from the terminal."
        } else {
            return "No items match your filters."
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func shortDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        return shortDateFormatter.string(from: d)
    }

    @ViewBuilder
    private func rowMenu(for p: Paper) -> some View {
        let prefs = store.prefs(for: p.id)
        Button("Open in Preview") { store.openInPreview(p) }
        Button("Reveal in Finder") { store.revealInFinder(p) }
        Divider()
        Button(prefs.read ? "Mark as Unread" : "Mark as Read") {
            store.setRead(!prefs.read, for: p.id)
        }
        Button(prefs.saved ? "Remove from Saved" : "Save") {
            store.setStarred(!prefs.saved, for: p.id)
        }
        Menu("Rate") {
            ForEach(1...5, id: \.self) { i in
                Button("\(i) star\(i == 1 ? "" : "s")") {
                    store.setRating(i, for: p.id)
                }
            }
            Divider()
            Button("Clear rating") { store.setRating(nil, for: p.id) }
        }
        Divider()
        if let arxiv = p.arxiv_id, !arxiv.isEmpty {
            Button("Open arXiv page") {
                if let url = URL(string: "https://arxiv.org/abs/\(arxiv)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if let doi = p.doi, !doi.isEmpty {
            Button("Open DOI") {
                if let url = URL(string: "https://doi.org/\(doi)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        Divider()
        Button("Move to Trash…", role: .destructive) {
            pendingDeleteID = p.id
        }
    }
}
