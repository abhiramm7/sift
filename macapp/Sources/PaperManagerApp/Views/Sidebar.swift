import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var filter: LibraryFilter

    var body: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let v = $0 { filter = v } }
        )) {
            Section("Library") {
                Label("All", systemImage: "tray.full")
                    .badge(store.papers.count)
                    .tag(LibraryFilter.all)
                Label("Unread", systemImage: "circle")
                    .badge(unreadCount)
                    .tag(LibraryFilter.unread)
                Label("Starred", systemImage: "star")
                    .badge(starredCount)
                    .tag(LibraryFilter.starred)
            }

            Section("Kind") {
                ForEach(PaperKind.allCases, id: \.self) { k in
                    Label(k.label + "s", systemImage: k.symbol)
                        .badge(store.papers.filter { $0.kind == k }.count)
                        .tag(LibraryFilter.kind(k))
                }
            }

            if !store.allTags.isEmpty {
                Section("Tags") {
                    ForEach(store.allTags.prefix(40), id: \.tag) { entry in
                        Label("#\(entry.tag)", systemImage: "tag")
                            .badge(entry.count)
                            .tag(LibraryFilter.tag(entry.tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var unreadCount: Int {
        store.papers.filter { !store.prefs(for: $0.id).read }.count
    }

    private var starredCount: Int {
        store.papers.filter { store.prefs(for: $0.id).saved }.count
    }
}
