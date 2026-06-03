import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var filter: LibraryFilter
    @State private var tagSearch: String = ""
    @State private var showAllTags: Bool = false

    private let initialTagCount = 40

    var body: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let v = $0 { filter = v } }
        )) {
            Section("Library") {
                Label("All", systemImage: "tray.full")
                    .badge(store.papers.count)
                    .tag(LibraryFilter.all)
                Label("Unread", systemImage: "circle.dashed")
                    .badge(unreadCount)
                    .tag(LibraryFilter.unread)
                Label("Saved", systemImage: "bookmark")
                    .badge(starredCount)
                    .tag(LibraryFilter.starred)
                Label("Rated 4+", systemImage: "star.fill")
                    .badge(highlyRatedCount)
                    .tag(LibraryFilter.highlyRated)
            }

            Section("Kind") {
                ForEach(PaperKind.allCases, id: \.self) { k in
                    Label(k.label + "s", systemImage: k.symbol)
                        .badge(store.papers.filter { $0.kind == k }.count)
                        .tag(LibraryFilter.kind(k))
                }
            }

            if !store.allFolders.isEmpty {
                Section("Folders") {
                    ForEach(store.allFolders, id: \.folder) { entry in
                        Label(entry.folder, systemImage: "folder")
                            .badge(entry.count)
                            .tag(LibraryFilter.folder(entry.folder))
                    }
                }
            }

            if !store.allTags.isEmpty {
                Section {
                    if showAllTags {
                        TextField("Filter tags", text: $tagSearch)
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 2)
                    }
                    ForEach(filteredTags, id: \.tag) { entry in
                        Label("#\(entry.tag)", systemImage: "tag")
                            .badge(entry.count)
                            .tag(LibraryFilter.tag(entry.tag))
                    }
                    if !showAllTags, store.allTags.count > initialTagCount {
                        Button("Show all \(store.allTags.count) tags…") {
                            showAllTags = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                } header: {
                    HStack {
                        Text("Tags")
                        Spacer()
                        if showAllTags {
                            Button("Show top \(initialTagCount)") {
                                showAllTags = false
                                tagSearch = ""
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var filteredTags: [(tag: String, count: Int)] {
        let all = store.allTags
        let scoped = showAllTags ? all : Array(all.prefix(initialTagCount))
        let q = tagSearch.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return scoped }
        return scoped.filter { $0.tag.lowercased().contains(q) }
    }

    private var unreadCount: Int {
        store.papers.filter { !store.prefs(for: $0.id).read }.count
    }

    private var starredCount: Int {
        store.papers.filter { store.prefs(for: $0.id).saved }.count
    }

    private var highlyRatedCount: Int {
        store.papers.filter { (store.prefs(for: $0.id).rating ?? 0) >= 4 }.count
    }
}
