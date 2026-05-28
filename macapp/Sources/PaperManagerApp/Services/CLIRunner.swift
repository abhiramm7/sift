import Foundation

/// Thin wrapper that shells out to the user's installed `paper` CLI.
/// We look up the binary in a few well-known locations and the user's PATH.
enum CLIRunner {
    static let candidatePaths: [String] = [
        "/usr/local/bin/paper",
        "/opt/homebrew/bin/paper",
        "\(NSHomeDirectory())/.local/bin/paper",
        "\(NSHomeDirectory())/Archive/paper_manager/.venv/bin/paper",
    ]

    static let storedPathKey = "PaperManager.paperCLI"

    static func resolveBinary() -> URL? {
        if let stored = UserDefaults.standard.string(forKey: storedPathKey),
           FileManager.default.isExecutableFile(atPath: stored) {
            return URL(fileURLWithPath: stored)
        }
        for p in candidatePaths where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    /// Run `paper <args>` and stream stdout/stderr line-by-line.
    /// Returns the process exit code. `onLine` is invoked on the main actor.
    @discardableResult
    static func run(args: [String], onLine: @escaping @MainActor (String) -> Void) async throws -> Int32 {
        let proc = Process()
        if let bin = resolveBinary() {
            proc.executableURL = bin
            proc.arguments = args
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["paper"] + args
        }

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try proc.run()

        let handle = pipe.fileHandleForReading
        let readTask = Task.detached(priority: .utility) {
            do {
                for try await line in handle.bytes.lines {
                    await onLine(line)
                }
            } catch {
                // pipe closed or read failure — fine, just stop streaming.
            }
        }

        let code: Int32 = await withCheckedContinuation { cont in
            proc.terminationHandler = { p in
                cont.resume(returning: p.terminationStatus)
            }
        }
        _ = await readTask.value
        return code
    }
}
