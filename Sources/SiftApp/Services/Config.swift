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

    /// Best-effort detection of a consumer cloud-sync folder by path. Sift just
    /// writes plain files, so anything a desktop sync client mirrors (iCloud
    /// Drive, Google Drive, Dropbox, OneDrive) will sync the library. Returns a
    /// display name, or nil for an ordinary local folder.
    static func cloudProviderName(for url: URL) -> String? {
        let p = url.path
        if p.contains("/Library/Mobile Documents/com~apple~CloudDocs/") { return "iCloud Drive" }
        if p.contains("/Library/CloudStorage/GoogleDrive") || p.contains("/Google Drive") { return "Google Drive" }
        if p.contains("/Library/CloudStorage/Dropbox") || p.contains("/Dropbox") { return "Dropbox" }
        if p.contains("/Library/CloudStorage/OneDrive") || p.contains("/OneDrive") { return "OneDrive" }
        return nil
    }

    /// Create the standard subdirectory layout. Safe to call repeatedly.
    func ensureLayout() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: userDir, withIntermediateDirectories: true)
    }
}
