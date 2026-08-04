import SwiftUI

@main
struct CodeProjectBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(settings: .shared, runManager: .shared)
        } label: {
            StatusIconView(runManager: .shared)
        }
        .menuBarExtraStyle(.menu)

        Window("Run Log", id: "runLog") {
            RunLogView(runManager: .shared)
        }
        .windowResizability(.contentSize)
    }
}

struct StatusIconView: View {
    @ObservedObject var runManager: RunManager

    var body: some View {
        Label(
            "Code Project Backup",
            systemImage: runManager.isRunning ? "arrow.triangle.2.circlepath" : "terminal"
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SchedulerService.shared.start()
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
