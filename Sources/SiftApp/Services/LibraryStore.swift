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

    /// Paper IDs currently mid-LLM-tagging. Views can use this for spinners.
    @Published var taggingInFlight: Set<String> = []
    /// Last detected LLM provider. Refreshed by `refreshLLMProvider()`.
    @Published var llmProvider: LLMTagger.Provider = .unavailable
    /// Hint shown in Settings when no provider resolves (or one is forced).
    @Published var llmDiagnostic: String?
    @Published var lastTaggerError: String?

    /// User preference for which provider to use. Persisted to UserDefaults.
    @Published var llmPreference: LLMTagger.Preference = LLMTagger.Preference(
        rawValue: UserDefaults.standard.string(forKey: "Sift.llmPreference") ?? "auto"
    ) ?? .auto {
        didSet {
            UserDefaults.standard.set(llmPreference.rawValue, forKey: "Sift.llmPreference")
            Task { await refreshLLMProvider() }
        }
    }

    /// User-selected Claude model alias ("default", "haiku", "sonnet", "opus", or a full model id).
    @Published var claudeModel: String = UserDefaults.standard.string(forKey: "Sift.claudeModel") ?? "default" {
        didSet {
            UserDefaults.standard.set(claudeModel, forKey: "Sift.claudeModel")
            Task { await refreshLLMProvider() }
        }
    }

    /// User-pinned Ollama model name. Empty = auto-pick.
    @Published var ollamaModel: String = UserDefaults.standard.string(forKey: "Sift.ollamaModel") ?? "" {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: "Sift.ollamaModel")
            Task { await refreshLLMProvider() }
        }
    }

    /// Locally-installed Ollama chat models. Refreshed on demand for the Settings picker.
    @Published var availableOllamaModels: [String] = []

    /// Library tag vocabulary — steers LLM tag generation toward existing tags.
    @Published var tagStore: TagStore

    init(config: AppConfig = AppConfig.load()) {
        self.config = config
        self.tagStore = TagStore(libraryRoot: config.iCloudRoot)
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
        // Refresh tag vocabulary from current paper set.
        self.tagStore.rebuildFromPapers(self.papers)
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

    /// All unique folders across the library, with paper counts. Uses each
    /// paper's `effectiveFolder` (user override if set, else the LLM's
    /// auto-assigned folder). Case-folded for uniqueness; the displayed name
    /// is the most common spelling among papers that share that key.
    var allFolders: [(folder: String, count: Int)] {
        var counts: [String: Int] = [:]
        var displays: [String: [String: Int]] = [:]  // key -> {spelling -> count}
        for p in papers {
            guard let f = p.effectiveFolder?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !f.isEmpty else { continue }
            let key = f.lowercased()
            counts[key, default: 0] += 1
            displays[key, default: [:]][f, default: 0] += 1
        }
        return counts.map { (key, count) -> (folder: String, count: Int) in
            let display = displays[key]?.max(by: { $0.value < $1.value })?.key ?? key
            return (display, count)
        }
        .sorted { $0.count > $1.count || ($0.count == $1.count && $0.folder < $1.folder) }
    }

    /// Folder names in their current canonical spelling, for the LLM prompt.
    /// Includes user-set folders so the LLM will reuse names the user has
    /// adopted, not just ones the LLM previously invented.
    var folderVocabulary: [String] {
        allFolders.map { $0.folder }
    }

    /// All authors across the library with paper counts. Every author across
    /// every position counts — so a paper by ["Abhiram", "Branko"] contributes
    /// one to each name. Case-folded dedup; the displayed spelling is the
    /// most common one for that case-folded key.
    var allAuthors: [(author: String, count: Int)] {
        var counts: [String: Int] = [:]
        var displays: [String: [String: Int]] = [:]
        for p in papers {
            for a in p.authors {
                let cleaned = a.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }
                let key = cleaned.lowercased()
                counts[key, default: 0] += 1
                displays[key, default: [:]][cleaned, default: 0] += 1
            }
        }
        return counts.map { (key, count) -> (author: String, count: Int) in
            let display = displays[key]?.max(by: { $0.value < $1.value })?.key ?? key
            return (display, count)
        }
        .sorted { $0.count > $1.count || ($0.count == $1.count && $0.author < $1.author) }
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

    /// Move the paper's library/<id>/ folder to the Trash and drop it from
    /// in-memory state. Reversible — user can drag it back out of Trash.
    func deletePaper(_ id: String) {
        let dir = config.paperDir(id)
        NSWorkspace.shared.recycle([dir]) { _, _ in }
        papers.removeAll { $0.id == id }
        // Always rewrite prefs.json — a prior session may have written an entry
        // even if this session never loaded it. Without this, deleted papers
        // leave ghost prefs entries on disk that accumulate over time.
        prefs.removeValue(forKey: id)
        writePrefs()
    }

    // MARK: - Metadata edits (write back to metadata.json)

    /// Read-modify-write a paper's metadata.json on disk. Then refresh that
    /// paper's entry in `papers` so the UI sees the change.
    private func updateMetadata(id: String, mutate: (inout [String: Any]) -> Void) {
        let url = config.metadataURL(id)
        guard let data = try? Data(contentsOf: url),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastScanError = "Couldn't read \(url.lastPathComponent)"
            return
        }
        mutate(&obj)
        do {
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url, options: .atomic)
            refreshPaperOnDisk(id: id)
        } catch {
            lastScanError = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Set the paper's title. Used by the inline editor when PDFKit gave a junky
    /// title or the LLM heuristic missed a real-but-wrong title.
    func setTitle(_ title: String, for id: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateMetadata(id: id) { $0["title"] = cleaned }
    }

    /// Set the paper's kind (paper / book / report).
    func setKind(_ kind: PaperKind, for id: String) {
        updateMetadata(id: id) { $0["kind"] = kind.rawValue }
    }

    /// Set the paper's user_tags. Replaces the entire array — caller normalizes.
    func setUserTags(_ tags: [String], for id: String) {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let deduped = cleaned.filter { seen.insert($0).inserted }
        updateMetadata(id: id) { $0["user_tags"] = deduped }
        // Refresh vocabulary so the sidebar tag list and LLM prompt see the change.
        tagStore.rebuildFromPapers(papers)
    }

    func addUserTag(_ tag: String, for id: String) {
        guard let p = papers.first(where: { $0.id == id }) else { return }
        let new = p.user_tags + [tag]
        setUserTags(new, for: id)
    }

    func removeUserTag(_ tag: String, for id: String) {
        guard let p = papers.first(where: { $0.id == id }) else { return }
        let lower = tag.lowercased()
        let new = p.user_tags.filter { $0.lowercased() != lower }
        setUserTags(new, for: id)
    }

    func setStarred(_ saved: Bool, for id: String) {
        var e = prefs[id] ?? PrefsEntry()
        e.saved = saved
        e.updated_at = Self.isoNow()
        prefs[id] = e
        writePrefs()
    }

    // MARK: - LLM tagging

    func refreshLLMProvider() async {
        let (p, diag) = await LLMTagger.detectProvider(
            llmPreference,
            claudeModel: claudeModel,
            ollamaModel: ollamaModel)
        self.llmProvider = p
        self.llmDiagnostic = diag
        self.availableOllamaModels = await LLMTagger.listOllamaChatModels()
    }

    /// Read one paper's metadata.json from disk and replace it in `papers`.
    private func refreshPaperOnDisk(id: String) {
        let metaURL = config.metadataURL(id)
        guard let data = try? Data(contentsOf: metaURL),
              let p = try? JSONDecoder().decode(Paper.self, from: data) else { return }
        if let idx = papers.firstIndex(where: { $0.id == id }) {
            papers[idx] = p
        }
    }

    /// Bulk-tagging progress. nil when idle.
    @Published var bulkTagProgress: (done: Int, total: Int)? = nil

    /// Handle to the currently-running bulk-tag task. Used to cancel it.
    private var bulkTagTask: Task<Void, Never>?

    /// Per-paper task handles for individual (non-bulk) tagging. Cancellable.
    private var taggingTasks: [String: Task<Void, Never>] = [:]

    /// How many papers to tag concurrently in bulk mode.
    static let bulkConcurrency = 3

    /// How much of the PDF the LLM sees.
    enum TaggingMode {
        case fast    // first 3 pages — cheap, fits any provider, good for tagging
        case full    // provider's char cap — whole paper on Claude
    }

    /// Spawn a background task that runs the LLM tagger and writes results into
    /// metadata.json / summary.md. Silent on failure (no-op if no provider).
    /// - Parameter force: if false, skip papers that already have all fields.
    /// - Parameter mode: `.fast` (3 pages, default) or `.full` (provider cap).
    func generateTagsInBackground(for id: String, force: Bool = false, mode: TaggingMode = .fast) {
        // Replace any prior task for this paper.
        taggingTasks[id]?.cancel()
        taggingTasks[id] = Task { @MainActor [weak self] in
            await self?.runTagging(for: id, force: force, mode: mode)
            self?.taggingTasks.removeValue(forKey: id)
        }
    }

    /// Cancel an in-flight per-paper tagging operation. No-op if not running.
    /// This does NOT cancel a paper being tagged as part of `tagAllUntagged` —
    /// for that, use `cancelBulkTagging()`.
    func cancelTagging(for id: String) {
        taggingTasks[id]?.cancel()
    }

    // MARK: - Consolidate tags

    /// Ask the LLM to look at the current tag vocabulary and propose merges.
    /// Throws if no provider is available.
    func proposeTagMerges() async throws -> [LLMTagger.TagMergeProposal] {
        let (provider, _) = await LLMTagger.detectProvider(
            llmPreference, claudeModel: claudeModel, ollamaModel: ollamaModel)
        guard provider.isAvailable else { throw LLMTagger.TaggerError.noProvider }
        let vocab = Array(tagStore.vocabulary.values)
        return try await LLMTagger.proposeMerges(vocabulary: vocab, using: provider)
    }

    /// Apply a set of tag merges across every paper's metadata.json. For each
    /// merge, every occurrence of any `from` tag (in user_tags, auto.tags,
    /// auto.topics, auto.application_areas, auto.methods) is replaced with
    /// `into`. Duplicates after replacement are deduped. Then the vocabulary
    /// is rebuilt from the (now updated) paper set.
    func applyTagMerges(_ merges: [LLMTagger.TagMergeProposal]) {
        guard !merges.isEmpty else { return }

        // Build a single from→into lookup for O(1) renames.
        var renames: [String: String] = [:]
        for m in merges {
            for f in m.from {
                renames[f.lowercased()] = m.into.lowercased()
            }
        }
        guard !renames.isEmpty else { return }

        for p in papers {
            let metaURL = config.metadataURL(p.id)
            guard let data = try? Data(contentsOf: metaURL),
                  var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            var changed = false
            // Top-level user_tags
            if var ut = obj["user_tags"] as? [String] {
                let renamed = Self.renameList(ut, with: renames)
                if renamed != ut { ut = renamed; obj["user_tags"] = ut; changed = true }
            }
            // auto.*
            if var auto = obj["auto"] as? [String: Any] {
                for key in ["tags", "topics", "application_areas", "methods"] {
                    if let arr = auto[key] as? [String] {
                        let renamed = Self.renameList(arr, with: renames)
                        if renamed != arr {
                            auto[key] = renamed
                            changed = true
                        }
                    }
                }
                if changed { obj["auto"] = auto }
            }
            if changed {
                do {
                    let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
                    try out.write(to: metaURL, options: .atomic)
                } catch {
                    lastScanError = "Couldn't rewrite \(metaURL.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }

        // Reload all papers from disk and rebuild the vocabulary.
        Task { await self.rescan() }
    }

    /// Dedupe-preserving list rename: applies `renames` to each entry and drops
    /// duplicates (case-insensitive) while preserving original order.
    nonisolated private static func renameList(_ list: [String], with renames: [String: String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in list {
            let lower = t.lowercased()
            let new = renames[lower] ?? lower
            if seen.insert(new).inserted {
                out.append(new)
            }
        }
        return out
    }

    /// True if the paper still needs LLM work: tags, title, authors, summary,
    /// or folder missing/bad.
    func paperNeedsTagging(_ p: Paper) -> Bool {
        let noTags = p.auto?.tags?.isEmpty ?? true
        let badTitle = LLMTagger.isLikelyBadTitle(p.title)
        let badAuthors = LLMTagger.areLikelyBadAuthors(p.authors)
        let noSummary = (loadSummary(p) ?? "").isEmpty
        let noFolder = (p.auto?.folder?.isEmpty ?? true)
        return noTags || badTitle || badAuthors || noSummary || noFolder
    }

    /// Set the user's folder override. Stored at the top level as `user_folder`
    /// so the LLM's tagging pass (which writes `auto.folder`) never clobbers it.
    /// Pass nil to clear the override and fall back to the LLM's suggestion.
    func setUserFolder(_ folder: String?, for id: String) {
        let cleaned = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateMetadata(id: id) { obj in
            if let f = cleaned, !f.isEmpty {
                obj["user_folder"] = f
            } else {
                obj.removeValue(forKey: "user_folder")
            }
        }
    }

    /// Tag every paper that's missing tags / title / authors / summary. Runs
    /// `bulkConcurrency` LLM calls in parallel. Returns immediately — observe
    /// `bulkTagProgress` for progress, call `cancelBulkTagging()` to stop.
    func tagAllUntagged() {
        guard bulkTagTask == nil else { return }
        let ids = papers.compactMap { p -> String? in
            paperNeedsTagging(p) ? p.id : nil
        }
        guard !ids.isEmpty else { return }
        bulkTagProgress = (0, ids.count)
        let total = ids.count

        bulkTagTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.bulkTagTask = nil
                self.bulkTagProgress = nil
            }

            var done = 0
            var iter = ids.makeIterator()

            await withTaskGroup(of: Void.self) { group in
                let primeCount = min(Self.bulkConcurrency, total)
                for _ in 0..<primeCount {
                    if let id = iter.next() {
                        group.addTask { [weak self] in
                            await self?.runTagging(for: id, force: false, mode: .fast)
                        }
                    }
                }
                while await group.next() != nil {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    done += 1
                    self.bulkTagProgress = (done, total)
                    if let id = iter.next() {
                        group.addTask { [weak self] in
                            await self?.runTagging(for: id, force: false, mode: .fast)
                        }
                    }
                }
            }
        }
    }

    /// Cancel the running bulk-tag operation (if any). Each in-flight Claude
    /// subprocess gets a SIGTERM via `withTaskCancellationHandler`.
    func cancelBulkTagging() {
        bulkTagTask?.cancel()
    }

    /// Core tagging routine. Async so callers can await it; safe to call from
    /// a fire-and-forget `Task` too.
    private func runTagging(for id: String, force: Bool, mode: TaggingMode) async {
        guard !taggingInFlight.contains(id) else { return }
        taggingInFlight.insert(id)
        defer { taggingInFlight.remove(id) }

        let metaURL = config.metadataURL(id)
        let pdfURL = config.pdfURL(id)
        guard FileManager.default.fileExists(atPath: metaURL.path) else { return }

        guard let metaData = try? Data(contentsOf: metaURL),
              let obj = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] else {
            return
        }
        let existingTitle = (obj["title"] as? String) ?? ""
        let existingAuthors = (obj["authors"] as? [String]) ?? []
        let summaryURL = config.summaryURL(id)
        let hasSummary = FileManager.default.fileExists(atPath: summaryURL.path)
            && ((try? Data(contentsOf: summaryURL))?.isEmpty == false)
        if !force {
            let hasTags: Bool = {
                guard let auto = obj["auto"] as? [String: Any],
                      let existing = auto["tags"] as? [String] else { return false }
                return !existing.isEmpty
            }()
            let hasFolder: Bool = {
                guard let auto = obj["auto"] as? [String: Any],
                      let f = auto["folder"] as? String else { return false }
                return !f.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }()
            let titleOK = !LLMTagger.isLikelyBadTitle(existingTitle)
            let authorsOK = !LLMTagger.areLikelyBadAuthors(existingAuthors)
            if hasTags && titleOK && authorsOK && hasSummary && hasFolder { return }
        }

        // Provider must be resolved on the main actor (reads model prefs).
        let (provider, _) = await LLMTagger.detectProvider(
            llmPreference,
            claudeModel: claudeModel,
            ollamaModel: ollamaModel)
        guard provider.isAvailable else {
            self.lastTaggerError = "No LLM provider available."
            return
        }

        // Heavy work off the main actor: PDF text extraction + LLM call.
        // Trim text to fit the active provider's context budget AND the chosen mode.
        let textCap = LLMTagger.maxCharsForProvider(provider)
        let pageCap: Int
        switch mode {
        case .fast: pageCap = 3
        case .full: pageCap = .max
        }
        // Pre-rendered vocab passes to the LLM so it prefers existing tags.
        let vocabPrompt = tagStore.promptVocabulary(maxTags: 80)
        // Folder vocab — snapshot here on the main actor so the detached Task
        // can use it without touching `self`.
        let existingFolders = folderVocabulary
        let result: Result<LLMTagger.ExtractedInfo, Error> = await Task.detached(priority: .utility) {
            let text = LLMTagger.extractText(from: pdfURL, maxChars: textCap, maxPages: pageCap)
            do {
                let info = try await LLMTagger.extractInfo(
                    currentTitle: existingTitle,
                    text: text,
                    vocabulary: vocabPrompt,
                    existingFolders: existingFolders,
                    using: provider)
                return .success(info)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .failure(let error):
            self.lastTaggerError = error.localizedDescription
            return
        case .success(let info):
            guard !info.isEmpty else { return }

            // Canonicalize LLM-proposed tags against the library vocabulary —
            // exact match wins, near matches (case / hyphen / plural) snap to
            // existing, genuinely new tags pass through.
            var canon = info
            canon.topics = tagStore.canonicalize(info.topics)
            canon.applicationAreas = tagStore.canonicalize(info.applicationAreas)
            canon.methods = tagStore.canonicalize(info.methods)
            // Case-insensitive snap on folder: prevents "Machine Learning" /
            // "machine learning" duplicates.
            if let f = canon.folder {
                canon.folder = LLMTagger.canonicalizeFolder(f, against: existingFolders)
            }

            // Decide whether to overwrite the title: only if the existing one
            // looks bad AND the LLM's suggestion looks plausible.
            let titleUpdate: String? = {
                guard let proposed = canon.title,
                      LLMTagger.isLikelyBadTitle(existingTitle),
                      LLMTagger.isPlausibleTitle(proposed) else { return nil }
                return proposed
            }()
            // Same gating logic for authors.
            let authorsUpdate: [String]? = {
                guard let proposed = canon.authors,
                      LLMTagger.areLikelyBadAuthors(existingAuthors),
                      LLMTagger.arePlausibleAuthors(proposed) else { return nil }
                return proposed
            }()

            do {
                try Self.writeAutoInfo(canon, titleUpdate: titleUpdate, authorsUpdate: authorsUpdate, to: metaURL)
                // Fold the new tag set into the vocabulary so the next paper sees it.
                tagStore.recordUsage(canon.union)
                if let s = canon.summary, !s.isEmpty {
                    // Only write summary if there isn't already a user-curated one, OR
                    // if we're being forced. (Bulk run defaults to non-force, which
                    // means we already passed the hasSummary guard above for any paper
                    // that gets here — so it's safe to write.)
                    try s.write(to: summaryURL, atomically: true, encoding: .utf8)
                }
            } catch {
                self.lastTaggerError = "write failed: \(error.localizedDescription)"
                return
            }
            refreshPaperOnDisk(id: id)
        }
    }

    nonisolated private static func writeAutoInfo(
        _ info: LLMTagger.ExtractedInfo,
        titleUpdate: String?,
        authorsUpdate: [String]?,
        to url: URL
    ) throws {
        let data = try Data(contentsOf: url)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Sift", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "malformed metadata.json"])
        }
        var auto = (obj["auto"] as? [String: Any]) ?? [:]
        auto["topics"] = info.topics
        auto["application_areas"] = info.applicationAreas
        auto["methods"] = info.methods
        // Keep auto.tags as the flat union — used by sidebar tag list + search fallback.
        auto["tags"] = info.union
        // Only overwrite folder when the LLM produced one — don't clobber a
        // user-edited folder if the LLM (e.g. small ollama model) skipped it.
        if let f = info.folder, !f.isEmpty {
            auto["folder"] = f
        }
        obj["auto"] = auto
        if let newTitle = titleUpdate {
            obj["title"] = newTitle
        }
        if let newAuthors = authorsUpdate {
            obj["authors"] = newAuthors
        }
        let out = try JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
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
