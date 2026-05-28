import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case file, url
        var id: String { rawValue }
        var label: String { self == .file ? "Local PDF" : "URL / arXiv" }
    }

    @State private var mode: Mode = .file
    @State private var filePath: String = ""
    @State private var urlText: String = ""
    @State private var tags: String = ""
    @State private var isRunning: Bool = false
    @State private var statusLine: String = ""
    @State private var statusIsError: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add paper").font(.title3.weight(.semibold))

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .file:
                HStack {
                    TextField("Path to PDF", text: $filePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: chooseFile)
                }
                Text("Or drop a PDF onto this window — or the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .url:
                TextField("https://arxiv.org/abs/… , bare arXiv id, or direct PDF URL",
                          text: $urlText)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Tags (comma-separated, optional)", text: $tags)
                .textFieldStyle(.roundedBorder)

            if !statusLine.isEmpty {
                Label(statusLine, systemImage: statusIsError ? "xmark.octagon" : "checkmark.circle")
                    .foregroundStyle(statusIsError ? .red : .green)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isRunning ? "Adding…" : "Add") {
                    Task { await run() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || !canRun)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isRunning {
                ProgressView().controlSize(.large)
            }
        }
    }

    private var canRun: Bool {
        switch mode {
        case .file: return !filePath.isEmpty
        case .url: return !urlText.isEmpty
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            filePath = url.path
            mode = .file
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let first = providers.first else { return false }
        _ = first.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                filePath = url.path
                mode = .file
            }
        }
        return true
    }

    private func run() async {
        isRunning = true
        statusLine = ""
        statusIsError = false
        defer { isRunning = false }

        let ingest = IngestService(config: store.config)
        do {
            let result: IngestResult
            switch mode {
            case .file:
                let url = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)
                result = try await ingest.addLocalPDF(at: url, tags: tags)
            case .url:
                result = try await ingest.addArxivURL(urlText, tags: tags)
            }
            statusLine = result.alreadyExisted
                ? "Already in library (id \(result.paperId)) — metadata refreshed."
                : "Added paper \(result.paperId)."
            await store.rescan()
        } catch {
            statusLine = error.localizedDescription
            statusIsError = true
        }
    }
}
