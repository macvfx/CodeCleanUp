import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var runManager: RunManager

    var body: some View {
        Form {
            Section("Scan") {
                PathField(label: "Search root", path: $settings.searchRoot, chooseFile: false)
                PathField(label: "Report directory", path: $settings.reportDir, chooseFile: false)
            }

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

            Section("Cleanup") {
                Toggle("Run xcodebuild clean", isOn: $settings.doClean)
                Toggle("Remove matching DerivedData folders", isOn: $settings.doDerivedData)
            }

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

                switch settings.passwordMode {
                case .keychain:
                    KeychainPasswordRow(account: KeychainAccount.zipPassword)
                case .custom:
                    KeychainPasswordRow(account: KeychainAccount.customPassword)
                case .none:
                    EmptyView()
                }
            }

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
                    HStack {
                        Picker("Hour", selection: $settings.scheduleHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        Text(":")
                        Picker("Minute", selection: $settings.scheduleMinute) {
                            ForEach(0..<60, id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                    }
                }

                Text("Checks run every minute. Missed runs are caught up on the next launch or wake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $settings.exclusionsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 140)
            } header: {
                Text("Archive exclusions (one per line)")
            }

            Section {
                TextEditor(text: $settings.prunePathsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 90)
            } header: {
                Text("Paths pruned from scan (one per line)")
            }

            Section {
                HStack {
                    Button(runManager.isRunning ? "Running…" : "Run Backup Now") {
                        runManager.run(config: settings.makeRunConfiguration())
                    }
                    .disabled(runManager.isRunning)

                    if runManager.isRunning {
                        Button("Cancel") {
                            runManager.cancel()
                        }
                    }
                }
                if let summary = runManager.lastRunSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 620, minHeight: 720)
        .navigationTitle("Code Project Backup Settings")
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
