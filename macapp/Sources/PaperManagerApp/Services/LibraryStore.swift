import Foundation
import Combine
import AppKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published var papers: [Paper] = []
    @Published var prefs: PrefsMap = [:]
    @Published var config: AppConfig
    @Published var isScanning = false
    @Published var lastScanError: String?

    init(config: AppConfig = AppConfig.load()) {
        self.config = config
    }

    func rescan() async {
        isScanning = true
        defer { isScanning = false }

        let cfg = self.config
        let result = await Task.detached(priority: .userInitiated) { () -> (papers: [Paper], prefs: PrefsMap, error: String?) in
            var papers: [Paper] = []
            var prefs: PrefsMap = [:]
            var firstError: String?

            let fm = FileManager.default
            // Papers
            if let entries = try? fm.contentsOfDirectory(at: cfg.libraryDir, includingPropertiesForKeys: [.isDirectoryKey]) {
                for url in entries {
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: url.path, isDirectory: &isDir)
                    guard isDir.boolValue else { continue }
                    let meta = url.appendingPathComponent("metadata.json")
                    guard fm.fileExists(atPath: meta.path) else { continue }
                    do {
                        let data = try Data(contentsOf: meta)
                        let p = try JSONDecoder().decode(Paper.self, from: data)
                        papers.append(p)
                    } catch {
                        if firstError == nil {
                            firstError = "Failed to decode \(meta.lastPathComponent) in \(url.lastPathComponent): \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                firstError = "Library directory not readable: \(cfg.libraryDir.path)"
            }

            // Prefs
            if let data = try? Data(contentsOf: cfg.prefsFile),
               let map = try? JSONDecoder().decode(PrefsMap.self, from: data) {
                prefs = map
            }

            return (papers, prefs, firstError)
        }.value

        self.papers = result.papers.sorted { lhs, rhs in
            (lhs.addedDate ?? .distantPast) > (rhs.addedDate ?? .distantPast)
        }
        self.prefs = result.prefs
        self.lastScanError = result.error
    }

    func prefs(for id: String) -> PrefsEntry {
        prefs[id] ?? PrefsEntry()
    }

    /// All unique tags across the library (user_tags ∪ auto.tags).
    var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for p in papers {
            for t in p.allTags {
                counts[t, default: 0] += 1
            }
        }
        return counts
            .map { ($0.key, $0.value) }
            .sorted { $0.count > $1.count || ($0.count == $1.count && $0.tag < $1.tag) }
    }

    func openInPreview(_ paper: Paper) {
        let url = config.pdfURL(paper.id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ paper: Paper) {
        let dir = config.paperDir(paper.id)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    func loadSummary(_ paper: Paper) -> String? {
        let url = config.summaryURL(paper.id)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Mutations (write back to prefs.json)

    /// rating: -1 (down), 1..5 (stars), or nil to clear. Matches Python prefs.set_rating.
    func setRating(_ rating: Int?, for id: String) {
        var e = prefs[id] ?? PrefsEntry()
        e.rating = rating
        e.updated_at = Self.isoNow()
        prefs[id] = e
        writePrefs()
    }

    func setRead(_ read: Bool, for id: String) {
        var e = prefs[id] ?? PrefsEntry()
        e.read = read
        e.updated_at = Self.isoNow()
        prefs[id] = e
        writePrefs()
    }

    func setStarred(_ saved: Bool, for id: String) {
        var e = prefs[id] ?? PrefsEntry()
        e.saved = saved
        e.updated_at = Self.isoNow()
        prefs[id] = e
        writePrefs()
    }

    private func writePrefs() {
        do {
            try FileManager.default.createDirectory(
                at: config.userDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(prefs)
            try data.write(to: config.prefsFile, options: .atomic)
        } catch {
            lastScanError = "Failed to write prefs.json: \(error.localizedDescription)"
        }
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        // Python uses "+00:00" rather than "Z"; ISO8601DateFormatter emits "Z" by default,
        // which is the same UTC instant and round-trips fine through both decoders.
        return f.string(from: Date())
    }
}
