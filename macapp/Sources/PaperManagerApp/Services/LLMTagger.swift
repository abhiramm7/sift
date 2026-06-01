import Foundation
import PDFKit

/// Generates categorized topical tags (topics, application areas, methods) for
/// a paper using whichever LLM is available locally. Preference:
/// Claude CLI > Ollama chat model > none. Both are optional — if neither is
/// present, ingest still works; tags are just empty.
enum LLMTagger {

    /// Default cap on PDF text. ~200k chars ≈ 50k tokens, well within Claude's
    /// 200k-token context. See `maxCharsForProvider(_:)` for per-provider caps.
    static let maxPromptChars = 200_000

    /// Char cap per provider. Claude can swallow whole papers; small local Ollama
    /// models choke on long contexts (and run slow). We trim to ~3k tokens for
    /// Ollama — enough for title page + abstract + first sections.
    static func maxCharsForProvider(_ p: Provider) -> Int {
        switch p {
        case .claude: return maxPromptChars              // ~200k chars / ~50k tokens
        case .ollama: return 12_000                       // ~12k chars / ~3k tokens
        case .unavailable: return 0
        }
    }

    enum Provider: Equatable {
        case claude(binary: URL, model: String?)  // model = nil ⇒ CLI default
        case ollama(model: String)
        case unavailable

        var label: String {
            switch self {
            case .claude(_, let m): return "Claude CLI (\(m ?? "default model"))"
            case .ollama(let m): return "Ollama (\(m))"
            case .unavailable: return "no LLM detected"
            }
        }

        var isAvailable: Bool {
            if case .unavailable = self { return false }
            return true
        }

        var modelName: String? {
            switch self {
            case .claude(_, let m): return m
            case .ollama(let m): return m
            case .unavailable: return nil
            }
        }
    }

    /// LLM-extracted info: title, authors, summary, and categorized tags.
    struct ExtractedInfo: Equatable {
        var title: String?           // human-readable, NOT kebab-case
        var authors: [String]?       // ["First Last", "Other Person", ...]
        var summary: String?         // markdown — written to summary.md
        var topics: [String]
        var applicationAreas: [String]
        var methods: [String]

        /// Flat union of tags, deduped — for `auto.tags` (legacy/search).
        var union: [String] {
            var seen = Set<String>()
            var out: [String] = []
            for t in topics + applicationAreas + methods {
                if seen.insert(t).inserted { out.append(t) }
            }
            return out
        }

        var isEmpty: Bool {
            (title?.isEmpty ?? true)
                && (authors?.isEmpty ?? true)
                && (summary?.isEmpty ?? true)
                && topics.isEmpty && applicationAreas.isEmpty && methods.isEmpty
        }
    }

    /// Claude model aliases users can pick from in Settings.
    static let claudeModelChoices = ["default", "haiku", "sonnet", "opus"]

    /// User preference for which provider to use.
    enum Preference: String, CaseIterable, Identifiable {
        case auto
        case claude
        case ollama
        case off

        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Auto (prefer Claude)"
            case .claude: return "Claude CLI only"
            case .ollama: return "Ollama only"
            case .off: return "Off"
            }
        }
    }

    enum TaggerError: LocalizedError {
        case noProvider
        case llmFailed(String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .noProvider:
                return "No LLM available. Install Claude Code, or run Ollama with a chat model (e.g. `ollama pull llama3.2:3b`)."
            case .llmFailed(let m): return "LLM call failed: \(m)"
            case .badResponse(let m): return "LLM returned bad response: \(m)"
            }
        }
    }

    static let claudeCandidatePaths = [
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "\(NSHomeDirectory())/.local/bin/claude",
        "\(NSHomeDirectory())/.claude/local/claude",
    ]

    /// Chat models we'd prefer for tagging, in priority order. ≥3B parameters
    /// is the practical floor — smaller models can't reliably emit the 6-key
    /// JSON schema. MLX variants are faster on Apple Silicon.
    static let ollamaModelPreference = [
        "qwen3.5:4b-mlx",
        "qwen3.5:4b",
        "qwen2.5:3b",
        "qwen2.5",
        "llama3.2:3b",
        "llama3.2",
        "llama3.1:8b",
        "llama3.1",
        "mistral",
        "phi3",
    ]

    /// Resolve the best provider given a preference and optional per-provider
    /// model overrides. Quick — does not invoke the LLM.
    static func detectProvider(
        _ pref: Preference = .auto,
        claudeModel: String? = nil,
        ollamaModel: String? = nil
    ) async -> (Provider, diagnostic: String?) {
        switch pref {
        case .off:
            return (.unavailable, "Auto-tagging is turned off in Settings.")

        case .claude:
            if let bin = resolveClaudeBinary() {
                return (.claude(binary: bin, model: normalizeClaudeModel(claudeModel)), nil)
            }
            return (.unavailable, "Claude CLI not found. Install Claude Code (https://claude.com/claude-code).")

        case .ollama:
            if let model = await resolveOllamaModel(preferred: ollamaModel) {
                return (.ollama(model: model), nil)
            }
            if await ollamaIsRunning() {
                return (.unavailable, "Ollama is running but no chat model is installed. Run `ollama pull llama3.2:3b`.")
            }
            return (.unavailable, "Ollama isn't responding at localhost:11434. Start it with `brew services start ollama`.")

        case .auto:
            if let bin = resolveClaudeBinary() {
                return (.claude(binary: bin, model: normalizeClaudeModel(claudeModel)), nil)
            }
            if let model = await resolveOllamaModel(preferred: ollamaModel) {
                return (.ollama(model: model), nil)
            }
            if await ollamaIsRunning() {
                return (.unavailable, "Ollama is running but no chat model is installed. Run `ollama pull llama3.2:3b` in Terminal — that's all you need for tagging.")
            }
            return (.unavailable, "Install Claude Code, or start Ollama with a chat model:  `ollama pull llama3.2:3b && brew services start ollama`.")
        }
    }

    /// Treat "default"/"" as nil so we don't pass --model.
    static func normalizeClaudeModel(_ raw: String?) -> String? {
        guard let r = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !r.isEmpty, r.lowercased() != "default" else { return nil }
        return r
    }

    static func ollamaIsRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.0
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Detection

    static func resolveClaudeBinary() -> URL? {
        let fm = FileManager.default
        for p in claudeCandidatePaths where fm.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let data = try? pipe.fileHandleForReading.readToEnd(),
               let s = String(data: data, encoding: .utf8) {
                let path = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty, fm.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        } catch {
            // ignore
        }
        return nil
    }

    static func resolveOllamaModel(preferred: String? = nil) async -> String? {
        let names = await listOllamaModels()
        guard !names.isEmpty else { return nil }
        // User-pinned model wins if it's actually installed.
        if let p = preferred?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            if let exact = names.first(where: { $0 == p || $0.hasPrefix("\(p):") }) {
                return exact
            }
            // user-pinned but not installed — fall through to auto.
        }
        for pref in ollamaModelPreference {
            if let match = names.first(where: { $0 == pref || $0.hasPrefix("\(pref):") }) {
                return match
            }
        }
        return names.first(where: { !isEmbedderModel($0) })
    }

    /// All installed Ollama models. Empty if Ollama isn't running.
    static func listOllamaModels() async -> [String] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = obj["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }
        } catch {
            return []
        }
    }

    /// Only chat-suitable Ollama models (filters out embedders).
    static func listOllamaChatModels() async -> [String] {
        await listOllamaModels().filter { !isEmbedderModel($0) }
    }

    static func isEmbedderModel(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("embed") || n.contains("bge-") || n.contains("nomic-embed")
    }

    // MARK: - Text extraction

    /// Extract text from a PDF, bounded by EITHER a page limit or a char cap
    /// (whichever hits first). Walks pages sequentially; handles missing pages.
    static func extractText(from pdf: URL, maxChars: Int = maxPromptChars, maxPages: Int = .max) -> String {
        guard let doc = PDFDocument(url: pdf) else { return "" }
        var out = ""
        out.reserveCapacity(min(maxChars, 32_768))
        let pageLimit = min(doc.pageCount, maxPages)
        for i in 0..<pageLimit {
            if out.count >= maxChars { break }
            guard let page = doc.page(at: i), let s = page.string else { continue }
            out += s
            out += "\n"
        }
        if out.count > maxChars {
            return String(out.prefix(maxChars))
        }
        return out
    }

    // MARK: - Public API

    /// Extract title + summary + categorized tags. Throws if no provider is available.
    /// `vocabulary` (optional) is a pre-rendered string of existing library tags
    /// that the LLM is told to prefer over inventing new ones.
    static func extractInfo(currentTitle: String, text: String, vocabulary: String = "", using provider: Provider) async throws -> ExtractedInfo {
        let prompt = buildPrompt(currentTitle: currentTitle, text: text, vocabulary: vocabulary)
        let raw: String
        switch provider {
        case .claude(let bin, let model):
            raw = try await runClaude(bin: bin, model: model, prompt: prompt)
        case .ollama(let model):
            raw = try await runOllama(model: model, prompt: prompt)
        case .unavailable:
            throw TaggerError.noProvider
        }
        return parseExtractedInfo(from: raw)
    }

    // MARK: - Prompt

    static func buildPrompt(currentTitle: String, text: String, vocabulary: String = "") -> String {
        let vocabSection: String
        if vocabulary.isEmpty {
            vocabSection = ""
        } else {
            vocabSection = """


            EXISTING LIBRARY VOCABULARY
            Prefer these tags when they fit the paper. Invent a new tag ONLY when no existing tag captures the concept. If you use a new tag, follow the same kebab-case style.

            \(vocabulary)
            """
        }
        return """
        You extract structured info from academic documents for a personal library.

        Given the existing-title hint and the full text of a paper, book, or report, output a JSON object with SIX keys:

        - "title": the document's actual title, as a human-readable string. Look at the first page text and extract the real title. If the existing-title hint already looks like a real title, return it unchanged. If it looks like an arXiv ID (e.g. "2401.12345"), a filename, "Untitled", or otherwise junky, replace it with the title you find in the text. If you cannot find a confident title, return null.
        - "authors": array of human author names in the order they appear ("First Last", e.g. "Ashish Vaswani"). Exclude affiliations, emails, "et al.", and obvious non-people like "Microsoft Word", "LaTeX". Return an empty array if you cannot identify the authors confidently.
        - "summary": a short Markdown summary of the document. Use this exact structure: a "## TL;DR" section with 2 to 4 sentences explaining what the work is and why someone should care, followed by a "## Key contributions" section with 3 to 5 short bullet points. Keep total length under 200 words. Use ordinary English, not jargon. If you cannot summarize confidently, return null.
        - "topics": general subject areas the document fits into (3 to 5 tags). Examples: "machine-learning", "computer-vision", "hydrology", "climate-science", "operating-systems".
        - "application_areas": real-world problems or domains the work targets (1 to 4 tags). Examples: "drug-discovery", "machine-translation", "flood-forecasting", "autonomous-driving". Empty array if the work is purely theoretical.
        - "methods": specific techniques, algorithms, or model classes used or proposed (2 to 6 tags). Examples: "transformers", "graph-neural-networks", "monte-carlo", "kalman-filter", "diffusion-models".

        Rules:
        - Output ONLY a JSON object. No prose before or after, no markdown code fences around the JSON itself.
        - The "title", "authors", and "summary" values are normal human-readable strings (NOT kebab-case). Tags are lowercase kebab-case, ASCII letters/digits/hyphens only.
        - No author names, no years, no venue or publisher names in the tags.
        - No generic tags like "research", "study", "analysis", "paper", "method".
        - If a category does not apply, return an empty array — never omit the key.\(vocabSection)

        Existing title hint: \(currentTitle.isEmpty ? "(none)" : currentTitle)

        Text:
        \(text)
        """
    }

    // MARK: - Claude CLI

    /// Holder for a running Process so a cancellation handler can terminate it.
    private final class ProcessHolder: @unchecked Sendable {
        var proc: Process?
        func terminate() { proc?.terminate() }
    }

    /// Invoke `claude -p` with the prompt piped via stdin. argv has a length
    /// limit; stdin is unbounded. Cancels the subprocess if the task is cancelled.
    static func runClaude(bin: URL, model: String?, prompt: String) async throws -> String {
        let holder = ProcessHolder()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { () -> String in
                let proc = Process()
                proc.executableURL = bin
                var args = ["-p", "--no-session-persistence"]
                if let m = model, !m.isEmpty {
                    args.append(contentsOf: ["--model", m])
                }
                proc.arguments = args

                let inPipe = Pipe()
                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardInput = inPipe
                proc.standardOutput = outPipe
                proc.standardError = errPipe
                holder.proc = proc

                do {
                    try proc.run()
                } catch {
                    throw TaggerError.llmFailed("could not launch claude: \(error.localizedDescription)")
                }

                if let data = prompt.data(using: .utf8) {
                    try? inPipe.fileHandleForWriting.write(contentsOf: data)
                }
                try? inPipe.fileHandleForWriting.close()

                proc.waitUntilExit()

                if Task.isCancelled {
                    throw CancellationError()
                }

                let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()

                if proc.terminationStatus != 0 {
                    let msg = String(data: errData, encoding: .utf8) ?? "exit \(proc.terminationStatus)"
                    throw TaggerError.llmFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return String(data: outData, encoding: .utf8) ?? ""
            }.value
        } onCancel: {
            holder.terminate()
        }
    }

    // MARK: - Ollama

    static func runOllama(model: String, prompt: String) async throws -> String {
        // Use /api/chat (not /api/generate) so `think: false` works — critical for
        // reasoning models like qwen3.5 that otherwise burn the entire output
        // budget on hidden thinking tokens.
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else {
            throw TaggerError.llmFailed("invalid ollama URL")
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
            "think": false,                  // disable reasoning — qwen3.5 default-thinks for minutes otherwise
            "format": "json",
            "options": [
                "temperature": 0.1,
                "num_predict": 1000,          // hard safety cap (~750 tokens of JSON; way more than we need)
            ],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                throw TaggerError.llmFailed("ollama HTTP \(http.statusCode)")
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TaggerError.badResponse("not JSON")
            }
            // /api/chat shape: {"message":{"role":"assistant","content":"..."}}
            if let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? String {
                return content
            }
            // Fall back to /api/generate shape just in case.
            if let response = obj["response"] as? String {
                return response
            }
            throw TaggerError.badResponse("missing message.content")
        } catch let err as TaggerError {
            throw err
        } catch {
            throw TaggerError.llmFailed(error.localizedDescription)
        }
    }

    // MARK: - Parsing

    /// Parse the LLM response into ExtractedInfo. Tolerant of code fences,
    /// leading prose, or alternative key spellings.
    static func parseExtractedInfo(from raw: String) -> ExtractedInfo {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if working.hasPrefix("```") {
            working = String(working.dropFirst(3))
            if let nl = working.firstIndex(of: "\n") {
                let lang = working[..<nl].trimmingCharacters(in: .whitespaces).lowercased()
                if ["json", ""].contains(lang) {
                    working = String(working[working.index(after: nl)...])
                }
            }
            if let end = working.range(of: "```") {
                working = String(working[..<end.lowerBound])
            }
        }
        // Slice from first `{` to last `}` if there's leading/trailing prose.
        if let first = working.firstIndex(of: "{"),
           let last = working.lastIndex(of: "}"),
           first < last {
            working = String(working[first...last])
        }

        guard let data = working.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ExtractedInfo(title: nil, summary: nil, topics: [], applicationAreas: [], methods: [])
        }

        let title: String? = {
            guard let t = obj["title"] as? String else { return nil }
            let cleaned = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }()
        let authors: [String]? = {
            // Accept either ["A","B"] (preferred) or "A, B" (LLM goof).
            var raw: [String] = stringArray(from: obj["authors"])
            if raw.isEmpty, let single = obj["authors"] as? String {
                raw = single
                    .components(separatedBy: CharacterSet(charactersIn: ",;&"))
                    .flatMap { $0.components(separatedBy: " and ") }
            }
            let cleaned = raw
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 120 }
            return cleaned.isEmpty ? nil : Array(cleaned.prefix(20))
        }()
        let summary: String? = {
            guard let s = obj["summary"] as? String else { return nil }
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }()
        let topics = stringArray(from: obj["topics"])
        let apps = stringArray(from: obj["application_areas"] ?? obj["applications"] ?? obj["application areas"])
        let methods = stringArray(from: obj["methods"])

        return ExtractedInfo(
            title: title,
            authors: authors,
            summary: summary,
            topics: normalize(topics, max: 5),
            applicationAreas: normalize(apps, max: 4),
            methods: normalize(methods, max: 6))
    }

    // MARK: - Author heuristic

    private static let nonAuthorMarkers: Set<String> = [
        "microsoft word", "microsoft office", "latex", "pdflatex", "tex output",
        "adobe acrobat", "preview", "author", "authors", "unknown", "anonymous",
        "untitled", "pdfcreator", "pdftk", "lualatex", "xelatex", "ghostscript",
    ]

    /// True if the existing authors list looks like PDFKit metadata garbage
    /// (compile-tool names, single fragment, all numbers, etc.) and should be
    /// replaced by an LLM-extracted list.
    static func areLikelyBadAuthors(_ authors: [String]) -> Bool {
        if authors.isEmpty { return true }
        // All entries are junk → bad.
        for a in authors {
            let t = a.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return true }
            let lower = t.lowercased()
            if nonAuthorMarkers.contains(where: { lower.contains($0) }) { return true }
            // Mostly non-letters
            let letters = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            if Double(letters) / Double(t.count) < 0.5 { return true }
            // Single-token author with no spaces and not capitalised → suspicious
            if !t.contains(" ") && t.count < 4 { return true }
        }
        return false
    }

    /// True if the LLM's proposed authors look plausible (at least one entry,
    /// no obvious junk).
    static func arePlausibleAuthors(_ proposed: [String]) -> Bool {
        guard !proposed.isEmpty else { return false }
        return !areLikelyBadAuthors(proposed)
    }

    // MARK: - Title heuristic

    /// True if the current title looks like junk (filename / arxiv id / empty /
    /// "Untitled") and should be replaced by an LLM-extracted title.
    static func isLikelyBadTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if t.count < 5 { return true }
        let lower = t.lowercased()
        if lower == "untitled" || lower == "no title" { return true }
        if lower.hasSuffix(".pdf") { return true }

        // arXiv-id-ish: 2401.12345, 1706.03762v2, hep-th/0101001, plus optional vN
        if t.range(of: #"^\d{4}\.\d{4,5}(v\d+)?$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^[a-z\-]+/\d{7}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }

        // Mostly non-letters — likely a filename or compile artifact.
        let letterCount = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        if Double(letterCount) / Double(t.count) < 0.5 { return true }

        // Filename-ish underscores between digits
        if t.range(of: #"\d_|\b_\d|^_|_$"#, options: .regularExpression) != nil { return true }

        return false
    }

    /// True if `proposed` is a sensible-looking replacement title (not generic,
    /// not itself junky, has at least 2 letters and one space or 8+ chars).
    static func isPlausibleTitle(_ proposed: String) -> Bool {
        let t = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || isLikelyBadTitle(t) { return false }
        if t.count >= 8 { return true }
        if t.contains(" ") { return true }
        return false
    }

    private static func stringArray(from any: Any?) -> [String] {
        guard let arr = any as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }
    }

    static func normalize(_ tags: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for t in tags {
            var cleaned = t
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
                .replacingOccurrences(of: " ", with: "-")
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            cleaned = String(cleaned.unicodeScalars.filter { allowed.contains($0) })
            cleaned = cleaned.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard cleaned.count >= 2, cleaned.count <= 40 else { continue }
            if bannedTags.contains(cleaned) { continue }
            if seen.insert(cleaned).inserted {
                out.append(cleaned)
            }
            if out.count >= max { break }
        }
        return out
    }

    static let bannedTags: Set<String> = [
        "research", "study", "analysis", "paper", "papers", "method", "methods",
        "results", "introduction", "conclusion", "abstract", "report", "book",
        "document", "documents", "topic", "topics", "tag", "tags",
    ]
}
