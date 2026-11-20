import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var runManager: RunManager

    enum Pane: String, CaseIterable, Identifiable {
        case folders = "Folders", cleanup = "Cleanup", archive = "Archive", schedule = "Schedule", advanced = "Advanced"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .folders: return "folder"
            case .cleanup: return "trash"
            case .archive: return "archivebox"
            case .schedule: return "clock"
            case .advanced: return "slider.horizontal.3"
            }
        }
        var blurb: String {
            switch self {
            case .folders: return "What to scan and where reports go."
            case .cleanup: return "What a run removes before archiving."
            case .archive: return "The zip file and its password."
            case .schedule: return "When backups run by themselves."
            case .advanced: return "Exclusion and prune rules."
            }
        }
    }

    @State private var pane: Pane = .folders

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(Pane.allCases, selection: $pane) { p in
                        Label(p.rawValue, systemImage: p.icon).tag(p)
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarLink("Run Log", "doc.plaintext") { RunLogWindowController.shared.show() }
                        sidebarLink("Reports", "folder") { openFolder(settings.resolvedReportDir) }
                        sidebarLink("Archives", "archivebox") { openFolder(archiveFolder) }
                        sidebarLink("Help", "questionmark.circle") { HelpWindowController.shared.show() }
                        sidebarLink("Updates", "arrow.down.circle") { AppDelegate.current?.updater.checkNow() }
                    }
                    .padding(8)
                }
                .frame(width: 180)
                .background(Color.primary.opacity(0.06))

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pane.rawValue).font(.title.bold())
                        Text(pane.blurb).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    paneForm
                }
            }
            Divider()
            runBar
        }
        .frame(minWidth: 820, minHeight: 640)
        .navigationTitle("Code Project Backup Settings")
    }

    @ViewBuilder private var paneForm: some View {
        Form {
            switch pane {
            case .folders:
                scanSection
                reportSection
            case .cleanup:
                cleanupSection
            case .archive:
                archiveSection
            case .schedule:
                scheduleSection
            case .advanced:
                exclusionsSection
                pruneSection
            }
        }
        .formStyle(.grouped)
        // A pane taller than the window scrolls; without this its first section title is
        // drawn over the pane's own title and blurb.
        .clipped()
    }

    private func sidebarLink(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openFolder(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path.expandingTilde(), isDirectory: true))
    }

    private var archiveFolder: String {
        let setting = settings.zipPath.trimmingCharacters(in: .whitespaces).isEmpty ? "~/Downloads" : settings.zipPath
        let expanded = setting.expandingTilde()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return expanded
        }
        return (expanded as NSString).deletingLastPathComponent
    }

    private var runBar: some View {
        HStack(spacing: 12) {
            Button(runManager.isRunning ? "Running\u{2026}" : "Back Up Now") {
                runManager.run(config: settings.makeRunConfiguration())
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
            .disabled(runManager.isRunning)

            if runManager.isRunning {
                Button("Cancel") { runManager.cancel() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
            }
            if let summary = runManager.lastRunSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var scanSection: some View {
        Section("Scan") {
            PathField(label: "Search root", path: $settings.searchRoot, chooseFile: false)
            PathField(label: "Report directory", path: $settings.reportDir, chooseFile: false)
        }
    }

    @ViewBuilder private var reportSection: some View {
        Section("Report") {
            TextField("Filename alias (optional)", text: $settings.reportAlias)
            HStack {
                Text("Filename")
                Spacer()
                Text("\(settings.reportFilenamePreview).txt / .csv")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text("Reports are written to \(settings.resolvedReportDir).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Run log: \(RunLogService.logPath)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder private var cleanupSection: some View {
        Section("Cleanup") {
            Toggle("Run xcodebuild clean", isOn: $settings.doClean)
            Toggle("Remove matching DerivedData folders", isOn: $settings.doDerivedData)
            Toggle("Remove .build and Xcode build-output folders in the search root", isOn: $settings.doRemoveBuildFolders)
            Text("Found by content (Build/Products, CompilationCache, …), not by name. Folders with git-tracked files or changed in the last hour are skipped. Use Preview Cleanup first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Xcode and developer tools") {
            Toggle("Also clear old Xcode leftovers", isOn: $settings.doDevTools)
            Text("Runs with the backup and on its schedule. Works outside the search root, in the Xcode folders in your Library. Everything goes to the Trash, so it can be put back; the space is freed when you empty it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                Toggle("Old Xcode archives", isOn: $settings.devArchives)
                if settings.devArchives {
                    Stepper(value: $settings.devArchiveDays, in: 7...730, step: 7) {
                        Text("Older than \(settings.devArchiveDays) days")
                    }
                    .padding(.leading, 20)
                    Text("The newest archive of each app is always kept, because it holds that build's debug symbols.")
                        .font(.caption).foregroundStyle(.secondary).padding(.leading, 20)
                }
                Toggle("Old device support (keeps the newest per device)", isOn: $settings.devDeviceSupport)
                Toggle("Xcode and SwiftPM caches (skipped while Xcode is open)", isOn: $settings.devCaches)
                Toggle("Unavailable simulator devices", isOn: $settings.devSimulators)
            }
            .disabled(!settings.doDevTools)
        }
    }

    @ViewBuilder private var archiveSection: some View {
        Section("Archive") {
            Toggle("Create zip archive", isOn: $settings.doArchive)
            PathField(
                label: "Archive path (empty = ~/Downloads)",
                path: $settings.zipPath,
                chooseFile: true
            )
            Picker("Password mode", selection: $settings.passwordMode) {
                ForEach(PasswordMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Always leave credential files out of the archive", isOn: $settings.excludeSecretsAlways)
            if settings.passwordMode == .none {
                Text("Password mode is None, so credential files (signing.env, .sentryclirc, .env, .p12 …) are left out automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch settings.passwordMode {
            case .keychain:
                KeychainPasswordRow(account: KeychainAccount.zipPassword)
            case .custom:
                KeychainPasswordRow(account: KeychainAccount.customPassword)
            case .none:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Schedule", selection: $settings.scheduleMode) {
                ForEach(ScheduleMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if settings.scheduleMode == .daily || settings.scheduleMode == .weekly {
                if settings.scheduleMode == .weekly {
                    Picker("Day", selection: $settings.scheduleWeekday) {
                        ForEach(1...7, id: \.self) { day in
                            Text(weekdayName(day)).tag(day)
                        }
                    }
                }
                DatePicker("Run at", selection: scheduleTimeBinding, displayedComponents: .hourAndMinute)
            }

            Text(scheduleSummary)
                .font(.callout)
                .foregroundStyle(settings.scheduleMode == .manual ? .secondary : .primary)

            Text("The time follows your Mac\u{2019}s clock setting (12 or 24 hour). Checks run every minute; a missed run is caught up on the next launch or wake.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var exclusionsSection: some View {
        Section {
            TextEditor(text: $settings.exclusionsText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 140)
        } header: {
            Text("Archive exclusions (one per line)")
        }
    }

    @ViewBuilder private var pruneSection: some View {
        Section {
            TextEditor(text: $settings.prunePathsText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 90)
        } header: {
            Text("Paths pruned from scan (one per line)")
        }
    }


    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(weekday - 1) % 7]
    }
}

struct PathField: View {
    let label: String
    @Binding var path: String
    let chooseFile: Bool

    var body: some View {
        HStack {
            TextField(label, text: $path)
            Button("Browse…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = chooseFile
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose"
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
        }
    }
}

struct KeychainPasswordRow: View {
    let account: String
    @State private var password = ""
    @State private var confirm = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("Password", text: $password)
            SecureField("Confirm", text: $confirm)
            HStack {
                Button("Save to Keychain") {
                    save()
                }
                Button("Clear") {
                    _ = KeychainService.deletePassword(account: account)
                    message = "Password cleared from Keychain."
                }
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if KeychainService.getPassword(account: account) != nil {
                message = "A password is saved in Keychain."
            }
        }
    }

    private func save() {
        guard !password.isEmpty else {
            message = "Password cannot be empty."
            return
        }
        guard password == confirm else {
            message = "Passwords do not match."
            return
        }
        if KeychainService.savePassword(password, account: account) {
            message = "Saved to Keychain."
            password = ""
            confirm = ""
        } else {
            message = "Failed to save password."
        }
    }
}


private extension SettingsView {
    /// Hour and minute are stored as ints; the picker works on a Date and follows the Mac's 12/24-hour setting.
    var scheduleTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.scheduleHour,
                                      minute: settings.scheduleMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.scheduleHour = c.hour ?? 0
                settings.scheduleMinute = c.minute ?? 0
            }
        )
    }

    /// One plain sentence saying exactly when it runs, in both 24-hour and 12-hour form.
    var scheduleSummary: String {
        let h = settings.scheduleHour, m = settings.scheduleMinute
        let twelve = h % 12 == 0 ? 12 : h % 12
        let time = String(format: "%02d:%02d (%d:%02d %@)", h, m, twelve, m, h < 12 ? "AM" : "PM")
        switch settings.scheduleMode {
        case .manual: return "Manual: runs only when you choose Back Up Now."
        case .hourly: return "Runs once an hour while the app is open."
        case .daily: return "Runs every day at \(time)."
        case .weekly: return "Runs every \(weekdayName(settings.scheduleWeekday)) at \(time)."
        }
    }
}
