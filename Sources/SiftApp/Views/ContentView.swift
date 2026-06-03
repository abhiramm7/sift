import SwiftUI
import UniformTypeIdentifiers

enum LibraryFilter: Hashable {
    case all
    case unread
    case starred
    case highlyRated    // rating >= 4
    case kind(PaperKind)
    case tag(String)
    case folder(String)
}

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var filter: LibraryFilter = .all
    @State private var selectedID: String?
    @State private var searchText: String = ""
    @State private var showAdd: Bool = false
    @State private var sortPreset: SortPreset = .recent
    @State private var sortOrder: [KeyPathComparator<Paper>] = SortPreset.recent.comparators
    @State private var dropStatus: String?
    @State private var isImporting: Bool = false

    var body: some View {
        NavigationSplitView {
            Sidebar(filter: $filter)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            PaperList(
                papers: filteredPapers,
                selectedID: $selectedID,
                searchText: $searchText,
                sortOrder: $sortOrder
            )
            .navigationSplitViewColumnWidth(min: 360, ideal: 480)
        } detail: {
            if let id = selectedID, let p = store.papers.first(where: { $0.id == id }) {
                PaperDetail(paper: p)
            } else {
                ContentUnavailableView(
                    "Select a paper",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Pick an item from the list to see details.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(SortPreset.allCases) { preset in
                        Button {
                            sortPreset = preset
                            // Rating sort needs prefs; PaperList sees empty
                            // comparators and applies the rating-aware sort.
                            sortOrder = preset.comparators
                        } label: {
                            if sortPreset == preset {
                                Label(preset.label, systemImage: "checkmark")
                            } else {
                                Text(preset.label)
                            }
                        }
                    }
                } label: {
                    Label("Sort: \(sortPreset.label)", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort the paper list")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add a paper (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                tagAllToolbar
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.rescan() }
                } label: {
                    if store.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help("Rescan iCloud (⌘R)")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddSheet()
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddSheet)) { _ in
            showAdd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshLibrary)) { _ in
            Task { await store.rescan() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFiles(providers)
            return true
        }
        .overlay(alignment: .bottom) {
            if let s = dropStatus {
                Text(s)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in
                    await ingestDropped(url: url)
                }
            }
        }
    }

    @ViewBuilder
    private var tagAllToolbar: some View {
        let count = store.papers.filter { store.paperNeedsTagging($0) }.count
        let providerAvailable = store.llmProvider.isAvailable

        if let progress = store.bulkTagProgress {
            HStack(spacing: 6) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text("\(progress.done)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    store.cancelBulkTagging()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Stop tagging")
            }
            .help("Tagging — \(progress.done) of \(progress.total) done")
        } else {
            Button {
                store.tagAllUntagged()
            } label: {
                if count > 0 {
                    Label("Tag \(count) paper\(count == 1 ? "" : "s")", systemImage: "sparkles")
                } else {
                    Label("Tag all", systemImage: "sparkles")
                }
            }
            .disabled(count == 0 || !providerAvailable)
            .help(
                !providerAvailable
                    ? "No LLM detected. Open Settings to choose Claude or Ollama."
                : count == 0
                    ? "All papers have tags and titles."
                : "Generate tags and fix bad titles for \(count) paper(s) via \(store.llmProvider.label)"
            )
        }
    }

    @MainActor
    private func ingestDropped(url: URL) async {
        isImporting = true
        defer { isImporting = false }
        let ingest = IngestService(config: store.config)
        do {
            let result = try await ingest.addLocalPDF(at: url)
            await store.rescan()
            if !result.alreadyExisted {
                store.generateTagsInBackground(for: result.paperId)
            }
            showStatus(result.alreadyExisted
                ? "Already in library: \(url.lastPathComponent)"
                : "Added \(url.lastPathComponent)")
        } catch {
            showStatus("Failed: \(error.localizedDescription)")
        }
    }

    private func showStatus(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            dropStatus = message
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if dropStatus == message { dropStatus = nil }
                }
            }
        }
    }

    private var filteredPapers: [Paper] {
        let base: [Paper]
        switch filter {
        case .all:
            base = store.papers
        case .unread:
            base = store.papers.filter { !store.prefs(for: $0.id).read }
        case .starred:
            base = store.papers.filter { store.prefs(for: $0.id).saved }
        case .highlyRated:
            base = store.papers.filter { (store.prefs(for: $0.id).rating ?? 0) >= 4 }
        case .kind(let k):
            base = store.papers.filter { $0.kind == k }
        case .tag(let t):
            let key = t.lowercased()
            base = store.papers.filter { paper in
                paper.allTags.contains { $0.lowercased() == key }
            }
        case .folder(let f):
            let key = f.lowercased()
            base = store.papers.filter { paper in
                (paper.effectiveFolder ?? "").lowercased() == key
            }
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { paper in
            if paper.title.lowercased().contains(q) { return true }
            if paper.authors.contains(where: { $0.lowercased().contains(q) }) { return true }
            if paper.allTags.contains(where: { $0.lowercased().contains(q) }) { return true }
            if let v = paper.venue, v.lowercased().contains(q) { return true }
            return false
        }
    }
}
