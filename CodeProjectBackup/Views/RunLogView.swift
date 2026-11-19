import AppKit
import SwiftUI

struct RunLogView: View {
    @ObservedObject var runManager: RunManager

    /// Path of a saved log picked from the menu; nil means the current or latest run.
    @State private var selectedPath: String?
    @State private var savedText = ""

    var body: some View {
        let text = displayText
        let warnings = RunLogView.extractWarnings(from: text)
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(warnings.count) warning\(warnings.count == 1 ? "" : "s") in this run", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 130)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.10)))
            }
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.06)))
        }
        .padding(12)
        .frame(minWidth: 600, minHeight: 380)
        .onAppear { selectedPath = nil; loadLatestIfNeeded() }
        .onChange(of: runManager.lastLogPath) { _, _ in
            selectedPath = nil
            loadLatestIfNeeded()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Latest run") { selectedPath = nil; loadLatestIfNeeded() }
                Divider()
                ForEach(RunLogService.recentRunLogs().prefix(20), id: \.path) { url in
                    Button(RunLogView.title(for: url)) {
                        selectedPath = url.path
                        savedText = (try? String(contentsOf: url, encoding: .utf8)) ?? "Could not read \(url.lastPathComponent)."
                    }
                }
            } label: {
                Label(currentTitle, systemImage: "clock.arrow.circlepath")
            }
            .fixedSize()

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayText, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                reveal()
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }

    private var currentTitle: String {
        if let selectedPath { return RunLogView.title(for: URL(fileURLWithPath: selectedPath)) }
        return runManager.isRunning ? "Current run" : "Latest run"
    }

    // MARK: - Content

    private var displayText: String {
        if selectedPath != nil { return savedText }
        if !runManager.logText.isEmpty { return runManager.logText }
        return savedText.isEmpty ? "No runs yet." : savedText
    }

    private func loadLatestIfNeeded() {
        guard runManager.logText.isEmpty, let newest = RunLogService.recentRunLogs().first else { return }
        savedText = (try? String(contentsOf: newest, encoding: .utf8)) ?? ""
    }

    private func reveal() {
        let path = selectedPath ?? runManager.lastLogPath
        if let path, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            let folder = URL(fileURLWithPath: RunLogService.logDirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    /// "2026-11-19 14:51 backup" from a file named 2026-11-19_14-51-04-backup.log.
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let halves = name.split(separator: "_", maxSplits: 1)
        guard halves.count == 2 else { return name }
        let pieces = halves[1].split(separator: "-")
        guard pieces.count >= 3 else { return name }
        return "\(halves[0]) \(pieces[0]):\(pieces[1]) \(pieces.dropFirst(3).joined(separator: "-"))"
    }

    /// The numbered lines under the WARNINGS block a run writes at its end.
    static func extractWarnings(from text: String) -> [String] {
        var inBlock = false
        var result: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("  WARNINGS (") {
                inBlock = true
                result = []
                continue
            }
            guard inBlock else { continue }
            if line.hasPrefix("====") { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            result.append(trimmed)
        }
        return result
    }
}
