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
    var exclusions: [String]
    var prunePaths: [String]
    var reportAlias: String
    var scheduleMode: ScheduleMode
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
        exclusionsText = defaults.string(forKey: "exclusionsText") ?? SettingsStore.defaultExclusions.joined(separator: "\n")
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
            exclusions: lines(from: exclusionsText),
            prunePaths: lines(from: prunePathsText),
            reportAlias: reportAlias,
            scheduleMode: scheduleMode
        )
    }

    private func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
