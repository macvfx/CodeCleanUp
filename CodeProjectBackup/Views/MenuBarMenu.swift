import SwiftUI

struct MenuBarMenu: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var runManager: RunManager
    var onCheckForUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            statusBanner
            actions
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Code Project Backup", systemImage: "externaldrive.badge.checkmark")
                .font(.headline)
            Spacer()
            Text(versionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    // MARK: - Status

    private var statusBanner: some View {
        let status = currentStatus
        return HStack(alignment: .top, spacing: 8) {
            if runManager.isRunning {
                ProgressView().controlSize(.small).padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(status.detail.isEmpty ? " " : status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = status.action {
                Button(action.title, action: action.run)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(status.tint.opacity(0.08)))
    }

    private struct Status {
        var title: String
        var detail: String
        var tint: Color
        var action: (title: String, run: () -> Void)?
    }

    private var currentStatus: Status {
        if runManager.isRunning {
            let title: String
            let detail: String
            switch runManager.runningKind {
            case .backup:
                title = runManager.stepText.isEmpty ? "Backing up…" : runManager.stepText
                detail = "Backup in progress."
            case .scan:
                title = runManager.stepText.isEmpty ? "Scanning…" : runManager.stepText
                detail = "Scan only: nothing is deleted or zipped."
            case .preview:
                title = runManager.stepText.isEmpty ? "Working out the preview…" : runManager.stepText
                detail = "Preview: nothing is deleted or zipped."
            }
            return Status(title: title, detail: detail, tint: .blue, action: nil)
        }
        if !FileManager.default.fileExists(atPath: settings.resolvedSearchRoot) {
            return Status(
                title: "Search folder not found",
                detail: settings.searchRoot,
                tint: .orange,
                action: ("Settings", { SettingsWindowController.shared.show() })
            )
        }
        guard let date = runManager.lastRunDate else {
            return Status(
                title: "No runs yet",
                detail: "Choose Preview to see what a run would do before you run it.",
                tint: .orange,
                action: nil
            )
        }
        let when = date.formatted(.relative(presentation: .named))
        let word: String
        switch runManager.lastRunKind {
        case .backup: word = "backup"
        case .scan: word = "scan"
        case .preview: word = "preview"
        }
        let detail = runManager.lastRunSummary ?? ""
        switch runManager.lastOutcome {
        case .ok:
            let action: (title: String, run: () -> Void)? = runManager.lastRunKind == .preview && runManager.lastPreview != nil
                ? ("Summary", { PreviewWindowController.shared.show() })
                : nil
            return Status(title: "Last \(word): \(when)", detail: detail, tint: .green, action: action)
        case .warnings:
            let count = runManager.lastWarnings.count
            let first = runManager.lastWarnings.first.map { count > 1 ? "\($0) (+\(count - 1) more)" : $0 } ?? detail
            return Status(title: "Last \(word) had \(count) warning\(count == 1 ? "" : "s"): \(when)", detail: first, tint: .orange,
                          action: ("View", { RunLogWindowController.shared.show() }))
        case .error:
            let reason = runManager.lastWarnings.first ?? detail
            return Status(title: "Last \(word) failed: \(when)", detail: reason, tint: .red,
                          action: ("View", { RunLogWindowController.shared.show() }))
        case .cancelled:
            return Status(title: "Last \(word) was cancelled: \(when)", detail: detail, tint: .orange, action: nil)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 8) {
            if runManager.isRunning {
                Button {
                    runManager.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.large)
            } else {
                Button {
                    runManager.run(config: settings.makeRunConfiguration())
                } label: {
                    Label("Back Up Now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .help("Runs everything turned on in Settings")

                HStack(spacing: 8) {
                    Button {
                        runManager.runPreviewCleanup(config: settings.makeRunConfiguration())
                    } label: {
                        Label("Preview", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Shows what a run would remove and zip. Changes nothing.")

                    Button {
                        runManager.runScanOnly(config: settings.makeRunConfiguration())
                    } label: {
                        Label("Scan", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Finds projects and build output, writes reports. Deletes and zips nothing.")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Footer

    /// Settings, Help and Updates are the larger row; the folders and log are the
    /// quiet row. Quit sits on its own at the right.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .center, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        mainLink("Settings", systemImage: "gearshape") { SettingsWindowController.shared.show() }
                        mainLink("Help", systemImage: "questionmark.circle") { HelpWindowController.shared.show() }
                        mainLink("Updates", systemImage: "arrow.down.circle") { onCheckForUpdates() }
                    }
                    GridRow {
                        quietLink("Run Log", systemImage: "doc.plaintext") { RunLogWindowController.shared.show() }
                        quietLink("Reports", systemImage: "folder") { openFolder(settings.resolvedReportDir) }
                        quietLink("Archives", systemImage: "archivebox") { openFolder(archiveFolder) }
                    }
                }
                Spacer(minLength: 8)
                Divider().frame(height: 46)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.title2)
                        Text("Quit")
                            .font(.callout.weight(.medium))
                    }
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 52)
                }
                .buttonStyle(.plain)
                .help("Quit Code Project Backup")
            }
        }
    }

    private func mainLink(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .imageScale(.large)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private func quietLink(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var archiveFolder: String {
        let setting = settings.zipPath.trimmingCharacters(in: .whitespaces).isEmpty
            ? "~/Downloads"
            : settings.zipPath
        let expanded = setting.expandingTilde()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return expanded
        }
        return (expanded as NSString).deletingLastPathComponent
    }

    private func openFolder(_ path: String) {
        let url = URL(fileURLWithPath: path.expandingTilde(), isDirectory: true)
        NSWorkspace.shared.open(url)
    }
}
