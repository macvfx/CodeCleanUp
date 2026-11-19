import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let rootView = SettingsView(settings: .shared, runManager: .shared)
            let controller = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: controller)
            window.title = "Code Project Backup Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 860, height: 680))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
