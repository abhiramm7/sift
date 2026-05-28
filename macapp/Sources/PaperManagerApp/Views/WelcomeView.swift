import SwiftUI
import AppKit

/// Shown on first run when no iCloud root is configured. Lets the user pick
/// where their library should live and creates the on-disk layout.
struct WelcomeView: View {
    @EnvironmentObject var store: LibraryStore
    @Binding var isPresented: Bool

    @State private var chosenPath: String = AppConfig.defaultRoot().path
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to PaperManager")
                    .font(.largeTitle.weight(.semibold))
                Text("A lightweight catalog for research papers and books. Your library is just a folder of PDFs and JSON — keep it in iCloud Drive and it syncs everywhere.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Where should your library live?")
                    .font(.headline)

                LabeledContent("Folder") {
                    HStack {
                        TextField("", text: $chosenPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        Button("Choose…", action: chooseFolder)
                    }
                }

                iCloudHint

                if let s = statusMessage {
                    Label(s, systemImage: statusIsError ? "xmark.octagon" : "checkmark.circle")
                        .foregroundStyle(statusIsError ? .red : .green)
                        .font(.callout)
                }
            }

            Spacer()

            HStack {
                Button("Use iCloud Drive (recommended)") {
                    chosenPath = AppConfig.defaultRoot().path
                }
                .help("Default location inside iCloud Drive")

                Spacer()

                Button("Continue") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(chosenPath.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 560, height: 380)
    }

    @ViewBuilder
    private var iCloudHint: some View {
        let expanded = (chosenPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let inICloud = AppConfig.isInICloudDrive(url)
        let iCloudOK = AppConfig.iCloudAvailable

        VStack(alignment: .leading, spacing: 4) {
            if !iCloudOK {
                Label("iCloud Drive is not enabled on this Mac. The app will still work, but your library won't sync to other devices.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if inICloud {
                Label("This folder is inside iCloud Drive — it'll sync to your other Apple devices automatically.", systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("This folder is outside iCloud Drive. The library will be local-only.", systemImage: "externaldrive")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose where to keep your PaperManager library"
        panel.prompt = "Use this folder"
        panel.directoryURL = URL(fileURLWithPath:
            (chosenPath as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            chosenPath = url.path
        }
    }

    private func commit() {
        let url = URL(fileURLWithPath: (chosenPath as NSString).expandingTildeInPath)
        let cfg = AppConfig(iCloudRoot: url)
        do {
            try cfg.ensureLayout()
        } catch {
            statusMessage = "Could not create folder: \(error.localizedDescription)"
            statusIsError = true
            return
        }
        cfg.save()
        UserDefaults.standard.set(true, forKey: AppConfig.onboardingDoneKey)
        store.config = cfg
        isPresented = false
        Task { await store.rescan() }
    }
}
