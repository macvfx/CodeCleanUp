import AppKit
import SwiftUI

@MainActor
final class HelpWindowController {
    static let shared = HelpWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: HelpView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Code Project Backup Help"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 700, height: 520))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    private enum Topic: String, CaseIterable, Identifiable {
        case quickStart = "Quick Start"
        case buttons = "What each button does"
        case cleanup = "Build folder cleanup"
        case archive = "The zip archive"
        case schedule = "Scheduled runs"
        case troubleshooting = "Troubleshooting"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .quickStart: return "flag.checkered"
            case .buttons: return "cursorarrow.click"
            case .cleanup: return "trash.slash"
            case .archive: return "lock.doc"
            case .schedule: return "clock"
            case .troubleshooting: return "wrench.and.screwdriver"
            }
        }

        var lines: [String] {
            switch self {
            case .quickStart:
                return [
                    "Open Settings and set the Search root to the folder that holds your code projects.",
                    "Choose Preview in the menu first. It shows what a run would remove and what the zip would contain, and it changes nothing.",
                    "In Settings, decide whether to turn on build folder removal. It is off by default.",
                    "Set an archive location and a password mode. Keychain mode saves the password once, for unattended runs.",
                    "Press Back Up Now, or set a schedule and leave it.",
                ]
            case .buttons:
                return [
                    "Back Up Now (blue) runs everything you have turned on in Settings: Xcode clean, DerivedData removal, build folder removal, the zip, and the reports.",
                    "Scan finds Xcode projects and measures build output, then writes the reports. It deletes and zips nothing.",
                    "Preview does the scan, lists the build folders a run would remove, and works out what the zip would contain: the number of files, the size before compression, and what the exclusions leave out. It opens a summary window. Nothing is deleted or zipped.",
                    "Cancel (orange) stops the run between steps and ends a zip that is in progress.",
                    "Run Log shows the full output of the last run. Reports and Archives open the folders where those files go.",
                ]
            case .cleanup:
                return [
                    "Build output is found by what a folder contains (Build/Products, a compilation cache, module caches, SwiftPM .build), not by its name. Folders such as Build, BuildPortFix and build are found, and a source folder that only shares a name is not.",
                    "A folder is never removed if git tracks any file in it, or if it changed in the last hour. Paths outside the Search root are refused.",
                    "Removal is off by default. Preview shows exactly what would go before you turn it on.",
                    "Everything removed is rebuilt by Xcode or SwiftPM on the next build, so the next build is slower.",
                    "Xcode and developer tools (Settings, Cleanup) is a separate, optional step that runs with the backup, on its schedule. It works outside the search root and moves old Xcode archives, old device-support folders, Xcode and SwiftPM caches to the Trash, and deletes unavailable simulator devices. The newest archive of each app is always kept, since it holds that build's debug symbols; caches are left alone while Xcode is open. Preview lists what it would do. The space is freed when you empty the Trash.",
                ]
            case .archive:
                return [
                    "The zip leaves out build output, caches, virtual environments, worktrees, Archiware P5 container blocks (.p5b) and anything else in the exclusion list in Settings. Each line is a zip pattern and you can edit them.",
                    "Credential files (signing.env, .sentryclirc, .env, .p12, .mobileprovision, SSH keys) are left out automatically when there is no password, or always if you turn that setting on.",
                    "Zip's built-in encryption (ZipCrypto) is weak, and the password is visible to other local processes while zip runs. Keep the archive on trusted storage.",
                    "Xcode's compilation cache can report tens of GB on almost no disk. It is excluded, because zip would otherwise read the full reported size.",
                ]
            case .schedule:
                return [
                    "Pick hourly, daily or weekly in Settings. The app checks every minute and catches up missed runs after a launch or wake.",
                    "Daily and weekly runs start at the \"Run at\" time, shown in your Mac's 12 or 24-hour style. A line under it spells out the schedule, such as \"Runs every day at 02:00 (2:00 AM).\"",
                    "Scheduled runs never prompt. They use the Keychain or Custom password, so save one first.",
                    "Each run adds a line to the run log and writes a report and CSV.",
                ]
            case .troubleshooting:
                return [
                    "If a scan or cleanup fails on a protected folder, give the app Full Disk Access in System Settings, Privacy & Security.",
                    "If the archive is skipped, the log says why: usually no saved password for the chosen password mode.",
                    "If a build folder you expected is listed as kept, the reason is shown beside it: tracked by git, or changed in the last hour.",
                    "Warnings are things that went wrong without stopping the run, such as a scheme that would not clean or a folder that could not be removed. The menu shows how many and the first one, and View opens the Run Log with all of them listed at the top.",
                    "Every run's complete log is saved, newest 40 kept, in ~/Library/Logs/CodeProjectBackup/runs. The Run Log window's clock menu switches between them and Show in Finder reveals the file. ~/Library/Logs/CodeProjectBackup/runs.log has one line per run, marked OK, WARN or ERROR.",
                    "Each report (.txt) lists the warnings of its run at the bottom.",
                ]
            }
        }
    }

    @State private var selected: Topic = .quickStart

    var body: some View {
        NavigationSplitView {
            List(Topic.allCases, selection: $selected) { topic in
                Label(topic.rawValue, systemImage: topic.icon)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selected.rawValue)
                        .font(.title2.weight(.semibold))
                    ForEach(Array(selected.lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if selected == .quickStart {
                                Text("\(index + 1).").foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
                            } else {
                                Text("•").foregroundStyle(.secondary)
                            }
                            Text(line).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
    }
}
