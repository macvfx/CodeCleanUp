import Foundation

enum PasswordMode: String, CaseIterable, Identifiable {
    case none
    case keychain
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .keychain: return "Keychain"
        case .custom: return "Custom"
        }
    }
}

enum ScheduleMode: String, CaseIterable, Identifiable {
    case manual
    case hourly
    case daily
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }
}

struct RunConfiguration {
    var searchRoot: String
    var reportDir: String
    var doClean: Bool
    var doDerivedData: Bool
    var doArchive: Bool
    var zipPath: String
    var passwordMode: PasswordMode
    var doRemoveBuildFolders: Bool
    var excludeSecretsAlways: Bool
    var exclusions: [String]
    var prunePaths: [String]
    var reportAlias: String
    var scheduleMode: ScheduleMode
    /// List what the build-folder step would remove, without deleting anything.
    var dryRunCleanup = false
    /// Also dry-run the archive (what would be zipped) and build a PreviewSummary.
    var previewArchive = false
    /// Whether "Create zip archive" is on in Settings, for the preview's notes.
    var archiveToggleOn = true
    /// Whether build-folder removal is on in Settings, for the preview's notes.
    var removeToggleOn = false
    /// Whether DerivedData removal is on in Settings, for the preview's notes.
    var derivedToggleOn = true
    /// Optional cleanup of Xcode archives, device support, caches and simulators,
    /// outside the search root. Off by default.
    var doDevTools = false
    var devTools = DevToolsOptions()
    /// Whether the developer-tools cleanup is on in Settings, for the preview's notes.
    var devToolsToggleOn = false
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let defaultExclusions: [String] = ArchiveService.defaultExclusions
    static let defaultPrunePaths: [String] = [
        "~/Library",
        "/System",
        "/Volumes",
        "/private",
        "/usr",
        "/opt"
    ]

    private let defaults = UserDefaults.standard

    @Published var searchRoot: String {
        didSet { defaults.set(searchRoot, forKey: "searchRoot") }
    }
    @Published var reportDir: String {
        didSet { defaults.set(reportDir, forKey: "reportDir") }
    }
    @Published var doClean: Bool {
        didSet { defaults.set(doClean, forKey: "doClean") }
    }
    @Published var doDerivedData: Bool {
        didSet { defaults.set(doDerivedData, forKey: "doDerivedData") }
    }
    @Published var doArchive: Bool {
        didSet { defaults.set(doArchive, forKey: "doArchive") }
    }
    @Published var zipPath: String {
        didSet { defaults.set(zipPath, forKey: "zipPath") }
    }
    @Published var passwordMode: PasswordMode {
        didSet { defaults.set(passwordMode.rawValue, forKey: "passwordMode") }
    }
    @Published var scheduleMode: ScheduleMode {
        didSet { defaults.set(scheduleMode.rawValue, forKey: "scheduleMode") }
    }
    @Published var scheduleHour: Int {
        didSet { defaults.set(scheduleHour, forKey: "scheduleHour") }
    }
    @Published var scheduleMinute: Int {
        didSet { defaults.set(scheduleMinute, forKey: "scheduleMinute") }
    }
    @Published var scheduleWeekday: Int {
        didSet { defaults.set(scheduleWeekday, forKey: "scheduleWeekday") }
    }
    @Published var lastScheduledRun: Date? {
        didSet {
            if let lastScheduledRun {
                defaults.set(lastScheduledRun, forKey: "lastScheduledRun")
            } else {
                defaults.removeObject(forKey: "lastScheduledRun")
            }
        }
    }
    /// Removes `.build` and Xcode build-output folders found by the scan. Off by default.
    @Published var doRemoveBuildFolders: Bool {
        didSet { defaults.set(doRemoveBuildFolders, forKey: "doRemoveBuildFolders") }
    }
    /// Also reclaim space used by Xcode and developer tools (archives, device support,
    /// caches, unavailable simulators). Runs with the backup, on the same schedule. Off by default.
    @Published var doDevTools: Bool {
        didSet { defaults.set(doDevTools, forKey: "doDevTools") }
    }
    @Published var devArchives: Bool {
        didSet { defaults.set(devArchives, forKey: "devArchives") }
    }
    @Published var devArchiveDays: Int {
        didSet { defaults.set(devArchiveDays, forKey: "devArchiveDays") }
    }
    @Published var devDeviceSupport: Bool {
        didSet { defaults.set(devDeviceSupport, forKey: "devDeviceSupport") }
    }
    @Published var devCaches: Bool {
        didSet { defaults.set(devCaches, forKey: "devCaches") }
    }
    @Published var devSimulators: Bool {
        didSet { defaults.set(devSimulators, forKey: "devSimulators") }
    }
    /// Skip credential files even when the archive is password-protected.
    @Published var excludeSecretsAlways: Bool {
        didSet { defaults.set(excludeSecretsAlways, forKey: "excludeSecretsAlways") }
    }
    @Published var exclusionsText: String {
        didSet { defaults.set(exclusionsText, forKey: "exclusionsText") }
    }
    @Published var prunePathsText: String {
        didSet { defaults.set(prunePathsText, forKey: "prunePathsText") }
    }
    @Published var reportAlias: String {
        didSet { defaults.set(reportAlias, forKey: "reportAlias") }
    }

    init() {
        searchRoot = defaults.string(forKey: "searchRoot") ?? "~/My Coding Projects"
        reportDir = defaults.string(forKey: "reportDir") ?? "~/Desktop"
        doClean = defaults.object(forKey: "doClean") as? Bool ?? true
        doDerivedData = defaults.object(forKey: "doDerivedData") as? Bool ?? true
        doArchive = defaults.object(forKey: "doArchive") as? Bool ?? true
        zipPath = defaults.string(forKey: "zipPath") ?? ""
        passwordMode = PasswordMode(rawValue: defaults.string(forKey: "passwordMode") ?? "") ?? .keychain
        scheduleMode = ScheduleMode(rawValue: defaults.string(forKey: "scheduleMode") ?? "") ?? .manual
        scheduleHour = defaults.object(forKey: "scheduleHour") as? Int ?? 2
        scheduleMinute = defaults.object(forKey: "scheduleMinute") as? Int ?? 0
        scheduleWeekday = defaults.object(forKey: "scheduleWeekday") as? Int ?? 1
        lastScheduledRun = defaults.object(forKey: "lastScheduledRun") as? Date
        doRemoveBuildFolders = defaults.object(forKey: "doRemoveBuildFolders") as? Bool ?? false
        doDevTools = defaults.object(forKey: "doDevTools") as? Bool ?? false
        devArchives = defaults.object(forKey: "devArchives") as? Bool ?? true
        devArchiveDays = defaults.object(forKey: "devArchiveDays") as? Int ?? 60
        devDeviceSupport = defaults.object(forKey: "devDeviceSupport") as? Bool ?? true
        devCaches = defaults.object(forKey: "devCaches") as? Bool ?? true
        devSimulators = defaults.object(forKey: "devSimulators") as? Bool ?? true
        excludeSecretsAlways = defaults.object(forKey: "excludeSecretsAlways") as? Bool ?? false
        var savedExclusions = defaults.string(forKey: "exclusionsText") ?? SettingsStore.defaultExclusions.joined(separator: "\n")
        // Saved settings override the defaults, so patterns added in a newer version
        // are appended once; the user's own edits and removals are otherwise kept.
        if defaults.integer(forKey: "exclusionsVersion") < ArchiveService.exclusionsVersion {
            let present = Set(savedExclusions.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
            let missing = SettingsStore.defaultExclusions.filter { !present.contains($0) }
            if !missing.isEmpty {
                savedExclusions += (savedExclusions.hasSuffix("\n") ? "" : "\n") + missing.joined(separator: "\n")
            }
            defaults.set(savedExclusions, forKey: "exclusionsText")
            defaults.set(ArchiveService.exclusionsVersion, forKey: "exclusionsVersion")
        }
        exclusionsText = savedExclusions
        prunePathsText = defaults.string(forKey: "prunePathsText") ?? SettingsStore.defaultPrunePaths.joined(separator: "\n")
        reportAlias = defaults.string(forKey: "reportAlias") ?? ""
    }

    var resolvedSearchRoot: String { searchRoot.expandingTilde() }
    var resolvedReportDir: String { reportDir.expandingTilde() }

    var reportFolderSlug: String {
        (resolvedSearchRoot as NSString).lastPathComponent.replacingOccurrences(of: " ", with: "_")
    }

    var reportFilenamePreview: String {
        let timestamp = Format.timestamp.string(from: Date())
        return ReportService.reportBaseName(alias: reportAlias, folderSlug: reportFolderSlug, timestamp: timestamp)
    }

    func makeRunConfiguration() -> RunConfiguration {
        RunConfiguration(
            searchRoot: searchRoot,
            reportDir: reportDir,
            doClean: doClean,
            doDerivedData: doDerivedData,
            doArchive: doArchive,
            zipPath: zipPath,
            passwordMode: passwordMode,
            doRemoveBuildFolders: doRemoveBuildFolders,
            excludeSecretsAlways: excludeSecretsAlways,
            exclusions: lines(from: exclusionsText),
            prunePaths: lines(from: prunePathsText),
            reportAlias: reportAlias,
            scheduleMode: scheduleMode,
            doDevTools: doDevTools,
            devTools: DevToolsOptions(
                archives: devArchives,
                archiveDays: devArchiveDays,
                deviceSupport: devDeviceSupport,
                caches: devCaches,
                simulators: devSimulators
            )
        )
    }

    private func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
