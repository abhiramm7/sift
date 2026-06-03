import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var filter: LibraryFilter
    @State private var tagSearch: String = ""
    @State private var showAllTags: Bool = false
    @State private var authorSearch: String = ""
    @State private var showAllAuthors: Bool = false

    private let initialTagCount = 40
    private let initialAuthorCount = 30

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

            Section("Folders") {
                if store.allFolders.isEmpty {
                    // Always show the section so first-time users know it's
                    // coming — otherwise a Folders section appearing later
                    // feels like a glitch (general-user agent caught this).
                    Text("Tag papers to fill this in.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 2)
                } else {
                    ForEach(store.allFolders, id: \.folder) { entry in
                        Label(entry.folder, systemImage: "folder")
                            .badge(entry.count)
                            .tag(LibraryFilter.folder(entry.folder))
                    }
                }
            }

            if !store.allAuthors.isEmpty {
                Section {
                    if showAllAuthors {
                        TextField("Filter authors", text: $authorSearch)
                            .textFieldStyle(.roundedBorder)
                            .padding(.vertical, 2)
                    }
                    ForEach(filteredAuthors, id: \.author) { entry in
                        Label(entry.author, systemImage: "person")
                            .badge(entry.count)
                            .tag(LibraryFilter.author(entry.author))
                    }
                    if !showAllAuthors, store.allAuthors.count > initialAuthorCount {
                        Button("Show all \(store.allAuthors.count) authors…") {
                            showAllAuthors = true
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                } header: {
                    HStack {
                        Text("Authors")
                        Spacer()
                        if showAllAuthors {
                            Button("Show top \(initialAuthorCount)") {
                                showAllAuthors = false
                                authorSearch = ""
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
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

    private var filteredAuthors: [(author: String, count: Int)] {
        let all = store.allAuthors
        let scoped = showAllAuthors ? all : Array(all.prefix(initialAuthorCount))
        let q = authorSearch.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return scoped }
        return scoped.filter { $0.author.lowercased().contains(q) }
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
