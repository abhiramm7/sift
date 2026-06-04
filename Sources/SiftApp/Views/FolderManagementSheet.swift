import SwiftUI

/// Sheet for renaming, merging, and deleting folders library-wide.
/// Not LLM-driven — folder cleanup is a workflow where the user knows what
/// they want (rename "ML" → "Machine Learning") and the LLM would add ceremony.
struct FolderManagementSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingFolder: String? = nil
    @State private var editDraft: String = ""
    @State private var deleteConfirm: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 360, idealHeight: 500)
        .alert(
            "Remove folder?",
            isPresented: Binding(
                get: { deleteConfirm != nil },
                set: { if !$0 { deleteConfirm = nil } }
            ),
            presenting: deleteConfirm
        ) { name in
            Button("Remove", role: .destructive) {
                store.renameFolder(from: name, to: nil)
                deleteConfirm = nil
            }
            Button("Cancel", role: .cancel) { deleteConfirm = nil }
        } message: { name in
            let count = store.allFolders.first(where: { $0.folder == name })?.count ?? 0
            Text("\"\(name)\" will be cleared from \(count) paper\(count == 1 ? "" : "s"). The papers stay in the library; they just won't have a folder until you set one or re-extract.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Manage folders")
                .font(.title3.weight(.semibold))
            Text("Rename a folder to fix what the LLM picked, or rename one folder to match another to merge them. Removing a folder clears it from those papers without deleting the papers themselves.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        if store.allFolders.isEmpty {
            ContentUnavailableView(
                "No folders yet",
                systemImage: "folder",
                description: Text("Tag papers to fill this in — the LLM assigns a subject-area folder during tagging."))
        } else {
            List {
                ForEach(store.allFolders, id: \.folder) { entry in
                    folderRow(entry)
                }
            }
            .listStyle(.inset)
        }
    }

    private func folderRow(_ entry: (folder: String, count: Int)) -> some View {
        // No leading folder icon: every row in this sheet is a folder.
        // The icon was visual noise without communicating anything new.
        HStack(spacing: 10) {
            if editingFolder == entry.folder {
                TextField("Folder name", text: $editDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(from: entry.folder) }
                Button("Save") { commitRename(from: entry.folder) }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel") {
                    editingFolder = nil
                    editDraft = ""
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Text(entry.folder)
                Spacer()
                Text("\(entry.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 24, alignment: .trailing)
                Button {
                    editingFolder = entry.folder
                    editDraft = entry.folder
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Rename — type a new name, or an existing folder's name to merge")
                Button(role: .destructive) {
                    deleteConfirm = entry.folder
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Clear this folder from every paper assigned to it")
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func commitRename(from oldName: String) {
        let cleaned = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            editingFolder = nil
            editDraft = ""
        }
        guard !cleaned.isEmpty, cleaned.lowercased() != oldName.lowercased() else { return }
        store.renameFolder(from: oldName, to: cleaned)
    }
}
