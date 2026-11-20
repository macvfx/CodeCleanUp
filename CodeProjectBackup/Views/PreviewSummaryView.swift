import AppKit
import SwiftUI

@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: PreviewSummaryView(runManager: .shared))
            let window = NSWindow(contentViewController: controller)
            window.title = "Preview"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 640, height: 720))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class RunLogWindowController {
    static let shared = RunLogWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: RunLogView(runManager: .shared))
            let window = NSWindow(contentViewController: controller)
            window.title = "Run Log"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 640, height: 420))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PreviewSummaryView: View {
    @ObservedObject var runManager: RunManager
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        if let preview = runManager.lastPreview {
            content(preview)
        } else {
            Text("No preview yet. Choose Preview from the menu bar.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(_ p: PreviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Preview — nothing was changed", systemImage: "eye")
                    .font(.title3.weight(.semibold))
                Text("\(p.searchRoot) · \(p.generatedAt.formatted(date: .abbreviated, time: .shortened)) · took \(p.elapsedSeconds)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    StatCard(
                        title: "Scanned",
                        value: "\(p.projectsScanned) project\(p.projectsScanned == 1 ? "" : "s")",
                        detail: "Xcode projects found. \(p.buildFolders.count) build folder\(p.buildFolders.count == 1 ? "" : "s") seen.",
                        tint: .secondary
                    )
                    StatCard(
                        title: "Would remove",
                        value: p.removable.isEmpty ? "Nothing" : "\(p.removable.count) folder\(p.removable.count == 1 ? "" : "s") · \(Format.human(p.removableKB))",
                        detail: removeDetail(p),
                        tint: p.removable.isEmpty && p.derivedDataFolders == 0 && p.devToolsItems == 0 ? .secondary : .green
                    )
                }
                GridRow {
                    StatCard(
                        title: "Would archive",
                        value: archiveValue(p),
                        detail: archiveDetail(p),
                        tint: .blue
                    )
                    StatCard(
                        title: "Left out",
                        value: p.excludedFiles.map { "\($0.formatted()) file\($0 == 1 ? "" : "s")" } ?? "—",
                        detail: leftOutDetail(p),
                        tint: .secondary
                    )
                }
            }

            if !p.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.10)))
            }

            GroupBox("Build folders") {
                if p.buildFolders.isEmpty {
                    Text("None found.").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(p.buildFolders, id: \.path) { folder in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(Format.human(folder.sizeKB))
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 70, alignment: .trailing)
                                    Text(relative(folder.path, to: p.searchRoot))
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 4)
                                    if let reason = folder.skipReason {
                                        Text("kept: \(reason)").font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: min(190, max(40, CGFloat(p.buildFolders.count) * 22)))
                }
            }

            if !p.excludedByRule.isEmpty {
                GroupBox("Left out of the archive, by rule") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(p.excludedByRule.prefix(8)) { rule in
                            HStack {
                                Text(rule.count.formatted())
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 70, alignment: .trailing)
                                Text(relativePattern(rule.pattern, to: p.searchRoot))
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(p.plainText, forType: .string)
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }
                Button {
                    RunLogWindowController.shared.show()
                } label: {
                    Label("Full Log", systemImage: "doc.plaintext")
                }
                Spacer()
                Button {
                    runManager.run(config: settings.makeRunConfiguration())
                } label: {
                    Label("Run Backup Now", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(runManager.isRunning)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 520)
    }

    private func removeDetail(_ p: PreviewSummary) -> String {
        var lines: [String] = []
        if p.removable.isEmpty {
            lines.append("No build folders to remove.")
        } else {
            lines.append(p.removalSettingOn
                ? "Build output that rebuilds."
                : "Build output that rebuilds. Removal is off in Settings, so a run keeps it.")
        }
        if p.derivedDataFolders > 0 {
            lines.append("DerivedData: \(p.derivedDataFolders) folder\(p.derivedDataFolders == 1 ? "" : "s"), \(Format.human(p.derivedDataKB)). Removal is \(p.derivedSettingOn ? "on" : "off") in Settings.")
        }
        if p.devToolsItems > 0 {
            lines.append("Xcode leftovers: \(p.devToolsItems) item\(p.devToolsItems == 1 ? "" : "s"), \(Format.human(p.devToolsKB)), moved to the Trash. Cleanup is \(p.devToolsSettingOn ? "on" : "off") in Settings.")
        }
        for note in p.devToolsNotes { lines.append(note) }
        return lines.joined(separator: "\n")
    }

    private func leftOutDetail(_ p: PreviewSummary) -> String {
        var lines = ["Skipped by the archive exclusions."]
        if !p.kept.isEmpty {
            lines.append("\(p.kept.count) build folder\(p.kept.count == 1 ? "" : "s") kept, not removed.")
        }
        if p.credentialFilesLeftOut {
            lines.append("Credential files left out.")
        }
        return lines.joined(separator: "\n")
    }

    private func archiveValue(_ p: PreviewSummary) -> String {
        guard let bytes = p.archiveBytes, let files = p.archiveFiles else { return "—" }
        return "\(Format.humanBytes(bytes))"
            + (files > 0 ? " · \(files.formatted()) files" : "")
    }

    private func archiveDetail(_ p: PreviewSummary) -> String {
        guard p.archiveBytes != nil else { return "could not be worked out" }
        var text = "before compression; the zip will be smaller"
        text += p.archiveEncrypted ? ". Password-protected." : ". Unencrypted."
        if !p.archiveSettingOn { text += " Zip archive is off in Settings." }
        return text
    }

    private func relative(_ path: String, to root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    /// Shows a generated per-folder pattern relative to the search root.
    private func relativePattern(_ pattern: String, to root: String) -> String {
        pattern.hasPrefix(root + "/") ? "…/" + pattern.dropFirst(root.count + 1) : pattern
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.08)))
    }
}
