import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var filter: LibraryFilter
    @State private var tagSearch: String = ""
    @State private var showAllTags: Bool = false
    @State private var authorSearch: String = ""
    @State private var showAllAuthors: Bool = false
    // Collapsed/expanded state persists across launches — Authors and Tags
    // can get long enough that the user wants them out of the way.
    @AppStorage("Sift.sidebarAuthorsExpanded") private var authorsExpanded: Bool = true
    @AppStorage("Sift.sidebarTagsExpanded") private var tagsExpanded: Bool = true

    // Sheets surfaced from the sidebar itself, not just Settings.
    @State private var showManageFolders: Bool = false
    @State private var showConsolidateAuthors: Bool = false
    @State private var showConsolidateTags: Bool = false

    // Inline rename / remove flows for a folder picked from the right-click menu.
    @State private var renameFolderTarget: String? = nil
    @State private var renameFolderDraft: String = ""
    @State private var removeFolderTarget: String? = nil

    private let initialTagCount = 40
    private let initialAuthorCount = 30

    var body: some View {
        listBody
            .listStyle(.sidebar)
            .sheet(isPresented: $showManageFolders) {
                FolderManagementSheet().environmentObject(store)
            }
            .sheet(isPresented: $showConsolidateAuthors) {
                ConsolidateAuthorsSheet().environmentObject(store)
            }
            .sheet(isPresented: $showConsolidateTags) {
                ConsolidateTagsSheet().environmentObject(store)
            }
            .alert(
                "Rename folder",
                isPresented: Binding(
                    get: { renameFolderTarget != nil },
                    set: { if !$0 { renameFolderTarget = nil } }
                ),
                presenting: renameFolderTarget,
                actions: renameAlertActions,
                message: renameAlertMessage)
            .alert(
                "Remove folder?",
                isPresented: Binding(
                    get: { removeFolderTarget != nil },
                    set: { if !$0 { removeFolderTarget = nil } }
                ),
                presenting: removeFolderTarget,
                actions: removeAlertActions,
                message: removeAlertMessage)
    }

    private var listBody: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let v = $0 { filter = v } }
        )) {
            librarySection
            kindSection
            foldersSection
            authorsSection
            tagsSection
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var librarySection: some View {
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
    }

    @ViewBuilder
    private var kindSection: some View {
        Section("Kind") {
            ForEach(PaperKind.allCases, id: \.self) { k in
                Label(k.label + "s", systemImage: k.symbol)
                    .badge(store.papers.filter { $0.kind == k }.count)
                    .tag(LibraryFilter.kind(k))
            }
        }
    }

    @ViewBuilder
    private var foldersSection: some View {
        Section {
            if store.allFolders.isEmpty {
                Text("Tag papers to fill this in.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(store.allFolders, id: \.folder) { entry in
                    folderRow(entry)
                }
            }
        } header: {
            sectionHeaderWithAction(
                title: "Folders",
                icon: "ellipsis.circle",
                enabled: !store.allFolders.isEmpty,
                helpEnabled: "Manage folders — rename, merge, remove",
                helpDisabled: "No folders yet — tag papers first.",
                action: { showManageFolders = true })
        }
    }

    @ViewBuilder
    private func folderRow(_ entry: (folder: String, count: Int)) -> some View {
        Label(entry.folder, systemImage: "folder")
            .badge(entry.count)
            .tag(LibraryFilter.folder(entry.folder))
            .contextMenu {
                Button("Rename folder…") {
                    renameFolderDraft = entry.folder
                    renameFolderTarget = entry.folder
                }
                Button("Remove folder…", role: .destructive) {
                    removeFolderTarget = entry.folder
                }
                Divider()
                Button("Manage all folders…") {
                    showManageFolders = true
                }
            }
    }

    @ViewBuilder
    private var authorsSection: some View {
        Section {
            if authorsExpanded {
                authorsBody
            }
        } header: {
            collapsibleHeader(
                title: "Authors",
                count: store.allAuthors.count,
                isExpanded: $authorsExpanded,
                trailing: { authorsHeaderTrailing })
        }
    }

    @ViewBuilder
    private var authorsBody: some View {
        if showAllAuthors {
            TextField("Filter authors", text: $authorSearch)
                .textFieldStyle(.roundedBorder)
                .padding(.vertical, 2)
        }
        if store.allAuthors.isEmpty {
            Text("Add some papers to fill this in.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 2)
        } else {
            ForEach(filteredAuthors, id: \.author) { entry in
                authorRow(entry)
            }
            if !showAllAuthors, store.allAuthors.count > initialAuthorCount {
                Button("Show all \(store.allAuthors.count) authors…") {
                    showAllAuthors = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func authorRow(_ entry: (author: String, count: Int)) -> some View {
        Label(entry.author, systemImage: "person")
            .badge(entry.count)
            .tag(LibraryFilter.author(entry.author))
            .contextMenu {
                Button("Consolidate authors…") {
                    showConsolidateAuthors = true
                }
                .disabled(!store.llmProvider.isAvailable)
            }
    }

    @ViewBuilder
    private var authorsHeaderTrailing: some View {
        if authorsExpanded && showAllAuthors {
            Button("Show top \(initialAuthorCount)") {
                showAllAuthors = false
                authorSearch = ""
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        Button {
            showConsolidateAuthors = true
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.borderless)
        .disabled(!store.llmProvider.isAvailable || store.allAuthors.count < 4)
        .help(store.llmProvider.isAvailable
              ? "Consolidate duplicate author names with the LLM"
              : "No LLM provider — see Settings")
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            if tagsExpanded {
                tagsBody
            }
        } header: {
            collapsibleHeader(
                title: "Tags",
                count: store.allTags.count,
                isExpanded: $tagsExpanded,
                trailing: { tagsHeaderTrailing })
        }
    }

    @ViewBuilder
    private var tagsBody: some View {
        if showAllTags {
            TextField("Filter tags", text: $tagSearch)
                .textFieldStyle(.roundedBorder)
                .padding(.vertical, 2)
        }
        if store.allTags.isEmpty {
            Text("Tag papers to fill this in.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 2)
        } else {
            ForEach(filteredTags, id: \.tag) { entry in
                tagRow(entry)
            }
            if !showAllTags, store.allTags.count > initialTagCount {
                Button("Show all \(store.allTags.count) tags…") {
                    showAllTags = true
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func tagRow(_ entry: (tag: String, count: Int)) -> some View {
        Label("#\(entry.tag)", systemImage: "tag")
            .badge(entry.count)
            .tag(LibraryFilter.tag(entry.tag))
            .contextMenu {
                Button("Consolidate tags…") {
                    showConsolidateTags = true
                }
                .disabled(!store.llmProvider.isAvailable)
            }
    }

    @ViewBuilder
    private var tagsHeaderTrailing: some View {
        if tagsExpanded && showAllTags {
            Button("Show top \(initialTagCount)") {
                showAllTags = false
                tagSearch = ""
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        Button {
            showConsolidateTags = true
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.borderless)
        .disabled(!store.llmProvider.isAvailable || store.allTags.count < 4)
        .help(store.llmProvider.isAvailable
              ? "Consolidate duplicate tags with the LLM"
              : "No LLM provider — see Settings")
    }

    // MARK: - Alerts

    @ViewBuilder
    private func renameAlertActions(_ name: String) -> some View {
        TextField("New name", text: $renameFolderDraft)
        Button("Save") {
            let cleaned = renameFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, cleaned.lowercased() != name.lowercased() {
                store.renameFolder(from: name, to: cleaned)
            }
            renameFolderTarget = nil
        }
        Button("Cancel", role: .cancel) {
            renameFolderTarget = nil
        }
    }

    private func renameAlertMessage(_ name: String) -> Text {
        Text("\"\(name)\" — typing the name of another folder merges them.")
    }

    @ViewBuilder
    private func removeAlertActions(_ name: String) -> some View {
        Button("Remove", role: .destructive) {
            store.renameFolder(from: name, to: nil)
            removeFolderTarget = nil
        }
        Button("Cancel", role: .cancel) {
            removeFolderTarget = nil
        }
    }

    private func removeAlertMessage(_ name: String) -> Text {
        let count = store.allFolders.first(where: { $0.folder == name })?.count ?? 0
        return Text("\"\(name)\" will be cleared from \(count) paper\(count == 1 ? "" : "s"). The papers stay; they just won't have a folder.")
    }

    // MARK: - Section header helpers

    /// Plain (non-collapsible) section header with a trailing action icon.
    /// Used for the Folders section, which always stays expanded.
    @ViewBuilder
    private func sectionHeaderWithAction(
        title: String,
        icon: String,
        enabled: Bool,
        helpEnabled: String,
        helpDisabled: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: icon)
            }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            .help(enabled ? helpEnabled : helpDisabled)
        }
    }

    /// Standard collapsible-section header: chevron + title; the whole header
    /// is a button that toggles `isExpanded`. When collapsed, shows the count
    /// so the user knows what's hidden. Optional trailing view sits on the
    /// right (e.g. the "Show top N" toggle and the ⋯ action button).
    @ViewBuilder
    private func collapsibleHeader<Trailing: View>(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    Text(title)
                    if !isExpanded.wrappedValue {
                        Text("(\(count))")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            trailing()
        }
    }

    // MARK: - Filtered lists

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
