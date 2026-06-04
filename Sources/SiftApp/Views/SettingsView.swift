import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore

    @State private var rootPath: String = ""
    @State private var showConsolidate: Bool = false
    @State private var showConsolidateAuthors: Bool = false
    @State private var showManageFolders: Bool = false

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("iCloud root") {
                    HStack {
                        TextField("", text: $rootPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…", action: chooseFolder)
                    }
                }
                HStack {
                    Spacer()
                    Button("Apply") {
                        let url = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)
                        store.config = AppConfig(iCloudRoot: url)
                        store.config.save()
                        Task { await store.rescan() }
                    }
                    .disabled(rootPath.isEmpty)
                }
            }

            Section("Auto-tagging") {
                Text("Optional. The app works without an LLM — ingest, search, ratings, and delete all work the same. Configure a provider only if you want titles, tags, and summaries filled in automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Use") {
                    Picker("", selection: Binding(
                        get: { store.llmPreference },
                        set: { store.llmPreference = $0 }
                    )) {
                        ForEach(LLMTagger.Preference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                }

                if store.llmPreference == .auto || store.llmPreference == .claude {
                    LabeledContent("Claude model") {
                        Picker("", selection: Binding(
                            get: { store.claudeModel },
                            set: { store.claudeModel = $0 }
                        )) {
                            ForEach(LLMTagger.claudeModelChoices, id: \.self) { m in
                                Text(m.capitalized).tag(m)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220)
                    }
                }

                if store.llmPreference == .auto || store.llmPreference == .ollama {
                    LabeledContent("Ollama model") {
                        HStack(spacing: 6) {
                            Picker("", selection: Binding(
                                get: { store.ollamaModel },
                                set: { store.ollamaModel = $0 }
                            )) {
                                Text("(auto)").tag("")
                                ForEach(store.availableOllamaModels, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 220)
                            Button {
                                Task { await store.refreshLLMProvider() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh list of installed Ollama models")
                        }
                    }
                }

                LabeledContent("Detected") {
                    HStack(spacing: 8) {
                        Image(systemName: store.llmProvider.isAvailable
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(store.llmProvider.isAvailable ? .green : .orange)
                        Text(store.llmProvider.label)
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(store.llmProvider.label)
                        Spacer(minLength: 8)
                        Button("Re-detect") {
                            Task { await store.refreshLLMProvider() }
                        }
                        .fixedSize()
                    }
                }
                if let diag = store.llmDiagnostic, !diag.isEmpty {
                    Text(diag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Tag vocabulary") {
                let top = store.tagStore.topTags(8)
                let total = store.tagStore.vocabulary.values.filter { $0.count > 0 }.count
                LabeledContent("Distinct tags") {
                    Text("\(total)").foregroundStyle(.secondary).monospacedDigit()
                }
                if !top.isEmpty {
                    // Stack top-tags vertically below their label so it never
                    // gets squeezed into the right column of LabeledContent.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top tags").font(.caption).foregroundStyle(.secondary)
                        Text(top.map { "\($0.name) (\($0.count))" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Reveal tags.json in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.tagStore.fileURL])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: store.tagStore.fileURL.path))
                    Button("Consolidate tags…") {
                        showConsolidate = true
                    }
                    .disabled(!store.llmProvider.isAvailable || total < 4)
                    .help(store.llmProvider.isAvailable
                          ? "Ask the LLM to find near-duplicate tags and propose merges"
                          : "No LLM provider available")
                }
                Text("Edit descriptions in tags.json to give the LLM extra semantic context. New tags are added automatically; canonicalization prefers existing tags over near-duplicates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Folders") {
                LabeledContent("Folders in library") {
                    Text("\(store.allFolders.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Manage folders…") {
                        showManageFolders = true
                    }
                    .disabled(store.allFolders.isEmpty)
                    .help(store.allFolders.isEmpty
                          ? "No folders yet — tag papers first."
                          : "Rename, merge, or remove folders library-wide.")
                }
                Text("Folder cleanup is manual on purpose — you know whether \"ML\" should become \"Machine Learning\" better than the LLM does. Renaming a folder to match another's name merges them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Authors") {
                LabeledContent("Distinct authors") {
                    Text("\(store.allAuthors.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Consolidate authors…") {
                        showConsolidateAuthors = true
                    }
                    .disabled(!store.llmProvider.isAvailable || store.allAuthors.count < 4)
                    .help(store.llmProvider.isAvailable
                          ? "Ask the LLM to find duplicate author names (\"J. Smith\" vs \"John Smith\") and propose merges."
                          : "No LLM provider available")
                }
                Text("PDFKit metadata often gives the same person under several spellings. This pass merges the obvious ones; it errs on the side of leaving things alone when ambiguous.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("About") {
                let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
                Text("Sift \(version) — collect, tag, rate, recall. Files live in the folder above as plain PDFs and JSON.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rootPath = store.config.iCloudRoot.path
            Task { await store.refreshLLMProvider() }
        }
        .sheet(isPresented: $showConsolidate) {
            ConsolidateTagsSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showConsolidateAuthors) {
            ConsolidateAuthorsSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showManageFolders) {
            FolderManagementSheet()
                .environmentObject(store)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.config.iCloudRoot
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
        }
    }
}
