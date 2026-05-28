import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore

    @State private var rootPath: String = ""
    @State private var cliPath: String = UserDefaults.standard.string(forKey: CLIRunner.storedPathKey) ?? ""
    @State private var detectedCLI: String = ""

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

            Section("paper CLI") {
                LabeledContent("Path") {
                    HStack {
                        TextField("(auto)", text: $cliPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Detect") {
                            detectedCLI = CLIRunner.resolveBinary()?.path ?? "not found in standard paths"
                            if let url = CLIRunner.resolveBinary() { cliPath = url.path }
                        }
                    }
                }
                if !detectedCLI.isEmpty {
                    Text(detectedCLI).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Save") {
                        if cliPath.isEmpty {
                            UserDefaults.standard.removeObject(forKey: CLIRunner.storedPathKey)
                        } else {
                            UserDefaults.standard.set(cliPath, forKey: CLIRunner.storedPathKey)
                        }
                    }
                }
            }

            Section("About") {
                Text("PaperManager 0.1 — reads the iCloud folder created by `paper init`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .onAppear {
            rootPath = store.config.iCloudRoot.path
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
