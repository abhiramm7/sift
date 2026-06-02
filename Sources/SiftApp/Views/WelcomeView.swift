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
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Sift")
                    .font(.largeTitle.weight(.semibold))
                Text("A fast, native catalog for research papers — no accounts, no server, no monthly fee. Your library is a regular folder of PDFs and JSON, so you can move it, back it up, or open files in any app.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Where should your library live?")
                    .font(.headline)

                // Friendly summary of where the library will be, not the raw path.
                folderSummary

                iCloudHint

                if let s = statusMessage {
                    Label(s, systemImage: statusIsError ? "xmark.octagon" : "checkmark.circle")
                        .foregroundStyle(statusIsError ? .red : .green)
                        .font(.callout)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Choose a different folder…", action: chooseFolder)
                Spacer()
                Button("Get started") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(chosenPath.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 560, height: 400)
    }

    /// Shows the chosen location as a human-readable line ("iCloud Drive · folder name"
    /// or just the folder name for non-iCloud paths). Raw path is in the tooltip.
    @ViewBuilder
    private var folderSummary: some View {
        let expanded = (chosenPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let inICloud = AppConfig.isInICloudDrive(url)
        let friendly: String = {
            if inICloud {
                return "iCloud Drive · " + url.lastPathComponent
            }
            // Show "~/Foo/Bar/Baz" style
            let home = NSHomeDirectory()
            if expanded.hasPrefix(home) {
                return "~" + expanded.dropFirst(home.count)
            }
            return expanded
        }()
        HStack(spacing: 10) {
            Image(systemName: inICloud ? "icloud" : "folder")
                .foregroundStyle(.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(friendly)
                    .font(.body.weight(.medium))
                Text(expanded)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
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
        panel.message = "Choose where to keep your Sift library"
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
