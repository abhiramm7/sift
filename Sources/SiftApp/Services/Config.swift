import Foundation

/// Mirrors the on-disk layout from the sibling Python project.
/// iCloud root defaults to ~/Library/Mobile Documents/com~apple~CloudDocs/PaperManager
/// — kept as the default folder name so existing libraries round-trip even after
/// the app was rebranded from "PaperManager" to "Sift". Users can choose any
/// other folder on first launch via WelcomeView.
struct AppConfig {
    var iCloudRoot: URL

    var libraryDir: URL { iCloudRoot.appendingPathComponent("library", isDirectory: true) }
    var inboxDir: URL { iCloudRoot.appendingPathComponent("inbox", isDirectory: true) }
    var userDir: URL { iCloudRoot.appendingPathComponent("user", isDirectory: true) }
    var prefsFile: URL { userDir.appendingPathComponent("prefs.json") }

    func paperDir(_ id: String) -> URL {
        libraryDir.appendingPathComponent(id, isDirectory: true)
    }
    func pdfURL(_ id: String) -> URL { paperDir(id).appendingPathComponent("paper.pdf") }
    func metadataURL(_ id: String) -> URL { paperDir(id).appendingPathComponent("metadata.json") }
    func summaryURL(_ id: String) -> URL { paperDir(id).appendingPathComponent("summary.md") }

    static func defaultRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("PaperManager", isDirectory: true)
    }

    static let storedRootKey = "Sift.iCloudRoot"
    static let onboardingDoneKey = "Sift.onboardingDone"

    static func load() -> AppConfig {
        if let stored = UserDefaults.standard.string(forKey: storedRootKey) {
            let url = URL(fileURLWithPath: (stored as NSString).expandingTildeInPath)
            return AppConfig(iCloudRoot: url)
        }
        return AppConfig(iCloudRoot: defaultRoot())
    }

    func save() {
        UserDefaults.standard.set(iCloudRoot.path, forKey: AppConfig.storedRootKey)
    }

    /// True iff the user has an iCloud account signed in.
    static var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// True iff a path lives inside the iCloud Drive container — what iCloud
    /// actually syncs across devices.
    static func isInICloudDrive(_ url: URL) -> Bool {
        let needle = "/Library/Mobile Documents/com~apple~CloudDocs/"
        return url.path.contains(needle)
    }

    /// Create the standard subdirectory layout. Safe to call repeatedly.
    func ensureLayout() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: userDir, withIntermediateDirectories: true)
    }
}
