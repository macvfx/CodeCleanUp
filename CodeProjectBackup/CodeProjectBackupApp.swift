import GitHubUpdateChecker
import SwiftUI

@main
struct CodeProjectBackupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(
                settings: .shared,
                runManager: .shared,
                onCheckForUpdates: { appDelegate.updater.checkNow() }
            )
        } label: {
            StatusIconView(runManager: .shared)
        }
        .menuBarExtraStyle(.window)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updater = UpdateCheckerViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SchedulerService.shared.start()
        updater.checkOnLaunch()
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
