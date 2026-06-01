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
