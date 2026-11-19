import SwiftUI

struct MenuBarMenu: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var runManager: RunManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Code Project Backup")
                .font(.headline)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()

            Button {
                runManager.run(config: settings.makeRunConfiguration())
            } label: {
                Label("Run Backup Now", systemImage: "play.fill")
            }
            .disabled(runManager.isRunning)

            Button {
                runManager.runScanOnly(config: settings.makeRunConfiguration())
            } label: {
                Label("Run Scan Only", systemImage: "magnifyingglass")
            }
            .disabled(runManager.isRunning)

            Button {
                runManager.runPreviewCleanup(config: settings.makeRunConfiguration())
            } label: {
                Label("Preview Build Cleanup", systemImage: "eye")
            }
            .disabled(runManager.isRunning)

            Button {
                runManager.cancel()
            } label: {
                Label("Cancel Run", systemImage: "stop.fill")
            }
            .disabled(!runManager.isRunning)

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "runLog")
            } label: {
                Label("Run Log", systemImage: "doc.plaintext")
            }

            Button {
                SettingsWindowController.shared.show()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }

            Divider()

            Button {
                openFolder(settings.resolvedReportDir)
            } label: {
                Label("Open Reports Folder", systemImage: "folder")
            }

            Button {
                openFolder(archiveFolder)
            } label: {
                Label("Open Archives Folder", systemImage: "folder")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .padding(4)
    }

    private var statusText: String {
        if runManager.isRunning {
            return "Backup in progress…"
        }
        if let summary = runManager.lastRunSummary {
            return "Last run: \(summary)"
        }
        return "Idle"
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
