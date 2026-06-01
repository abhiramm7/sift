import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore

    @State private var rootPath: String = ""

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
                        Text(store.llmProvider.label).font(.callout)
                        Spacer()
                        Button("Re-detect") {
                            Task { await store.refreshLLMProvider() }
                        }
                    }
                }
                if let diag = store.llmDiagnostic, !diag.isEmpty {
                    Text(diag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Tag vocabulary") {
                let top = store.tagStore.topTags(8)
                let total = store.tagStore.vocabulary.values.filter { $0.count > 0 }.count
                LabeledContent("Distinct tags") {
                    Text("\(total)").foregroundStyle(.secondary).monospacedDigit()
                }
                if !top.isEmpty {
                    LabeledContent("Top tags") {
                        Text(top.map { "\($0.name) (\($0.count))" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Reveal tags.json in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.tagStore.fileURL])
                    }
                    .disabled(!FileManager.default.fileExists(atPath: store.tagStore.fileURL.path))
                }
                Text("Edit descriptions in tags.json to give the LLM extra semantic context. New tags are added automatically; canonicalization prefers existing tags over near-duplicates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
                Text("PaperManager \(version) — standalone macOS catalog. Stores everything as plain files in the folder above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .onAppear {
            rootPath = store.config.iCloudRoot.path
            Task { await store.refreshLLMProvider() }
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
