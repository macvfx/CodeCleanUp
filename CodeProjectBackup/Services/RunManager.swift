import Foundation

/// Collects a run's log lines from the worker thread.
final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum RunKind {
    case backup, scan, preview
}

enum RunOutcome {
    case ok, warnings, error, cancelled
}

@MainActor
final class RunManager: ObservableObject {
    static let shared = RunManager()

    @Published var isRunning = false
    @Published var logText = ""
    @Published var lastRunSummary: String?
    /// What the running pipeline is doing now, for the menu.
    @Published var stepText = ""
    @Published var runningKind: RunKind = .backup
    @Published var lastRunDate: Date?
    @Published var lastRunKind: RunKind = .backup
    @Published var lastOutcome: RunOutcome = .ok
    @Published var lastPreview: PreviewSummary?
    /// Everything that went wrong without stopping the run, one line each.
    @Published var lastWarnings: [String] = []
    /// Where the last run's complete log was saved.
    @Published var lastLogPath: String?

    private var pipeline: PipelineRunner?

    func run(config: RunConfiguration, kind: RunKind = .backup) {
        guard !isRunning else { return }
        isRunning = true
        runningKind = kind
        stepText = "Starting…"
        logText = ""
        lastRunSummary = nil

        let runner = PipelineRunner(config: config)
        runner.onStep = { [weak self] text in
            DispatchQueue.main.async { self?.stepText = text }
        }
        pipeline = runner
        let sink = LogSink()
        let startedAt = Date()

        Task.detached(priority: .userInitiated) { [weak runner] in
            guard let runner else { return }
            let summary = runner.run { [weak self] message in
                sink.append(message)
                DispatchQueue.main.async {
                    self?.appendLog(message)
                }
            }
            // Keep the whole log on disk: the window only holds the current session's
            // last run, and the next run clears it.
            let kindName: String
            switch kind {
            case .backup: kindName = "backup"
            case .scan: kindName = "scan"
            case .preview: kindName = "preview"
            }
            let savedPath = RunLogService.saveRunLog(text: sink.text, kind: kindName, date: startedAt)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.pipeline = nil
                self.isRunning = false
                self.stepText = ""
                self.lastRunSummary = summary
                self.lastRunDate = Date()
                self.lastRunKind = kind
                self.lastOutcome = runner.outcome
                self.lastWarnings = runner.warnings
                self.lastLogPath = savedPath
                if kind == .preview, let preview = runner.previewSummary {
                    self.lastPreview = preview
                    PreviewWindowController.shared.show()
                }
            }
        }
    }

    func runScanOnly(config: RunConfiguration) {
        var config = config
        config.doClean = false
        config.doDerivedData = false
        config.doArchive = false
        config.doRemoveBuildFolders = false
        run(config: config, kind: .scan)
    }

    /// Lists the build folders that would be removed, deleting nothing.
    func runPreviewCleanup(config: RunConfiguration) {
        var config = config
        config.archiveToggleOn = config.doArchive
        config.removeToggleOn = config.doRemoveBuildFolders
        config.derivedToggleOn = config.doDerivedData
        config.doClean = false
        config.doDerivedData = false
        config.doArchive = false
        config.doRemoveBuildFolders = true
        config.dryRunCleanup = true
        config.previewArchive = true
        run(config: config, kind: .preview)
    }

    func cancel() {
        pipeline?.cancel()
    }

    private func appendLog(_ message: String) {
        if logText.isEmpty {
            logText = message
        } else {
            logText += "\n" + message
        }
    }
}

final class PipelineRunner {
    private let config: RunConfiguration
    private var isCancelled = false
    private var activeHandle: ProcessHandle?
    private var archiveFailed = false
    private var failureCount = 0

    /// Called at the start of each stage with a short description.
    var onStep: ((String) -> Void)?
    private(set) var previewSummary: PreviewSummary?
    private(set) var outcome: RunOutcome = .ok
    /// Problems that did not stop the run (a scheme that would not clean, a folder that
    /// could not be removed). Shown in the menu, the run log and the report.
    private(set) var warnings: [String] = []

    init(config: RunConfiguration) {
        self.config = config
    }

    func cancel() {
        isCancelled = true
        activeHandle?.terminate()
    }

    func run(log: @escaping (String) -> Void) -> String {
        logHandler = log
        let searchRoot = config.searchRoot.expandingTilde()
        let reportDir = config.reportDir.expandingTilde()
        let timestamp = Format.timestamp.string(from: Date())
        let slug = (searchRoot as NSString).lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let startedAt = Date()

        log("==============================================")
        log("  Code Project Backup")
        log("==============================================")
        log("  Search root : \(searchRoot)")
        log("  Report dir  : \(reportDir)")
        log("  Started     : \(Date())")
        log("")

        onStep?("Scanning for Xcode projects…")
        // Scheme detection runs xcodebuild -list on every project (minutes), and only
        // xcodebuild clean needs it.
        let scan = ProjectScanner.scan(searchRoot: searchRoot, prunePaths: config.prunePaths, detectSchemes: config.doClean, log: log)
        log("Found \(scan.containers.count) Xcode container(s), \(scan.buildFolders.count) build folder(s).")
        for container in scan.containers {
            let schemes = !container.schemesChecked ? "(not checked: only xcodebuild clean needs them)" : container.schemes.isEmpty ? "(no schemes)" : container.schemes.joined(separator: ", ")
            log("  [\(container.kind)] \(container.path)")
            log("    Schemes: \(schemes)")
        }
        for build in scan.buildFolders {
            let note = build.skipReason.map { "  [kept: \($0)]" } ?? ""
            log("  \(build.kind.rawValue) \(Format.human(build.sizeKB)) — \(build.path)\(note)")
        }
        log("")

        let derivedFolders = ProjectScanner.findDerivedDataFolders(bases: scan.uniqueBaseNames)
        var derivedSizeKB = 0
        for folder in derivedFolders {
            let kb = ProjectScanner.diskUsageKB(at: folder)
            derivedSizeKB += kb
            log("  DerivedData \(Format.human(kb)) — \(folder)")
        }
        log("DerivedData: \(derivedFolders.count) matching folder(s).")
        log("Estimated recoverable (build folders): \(Format.human(scan.removableBuildKB)) removable of \(Format.human(scan.buildTotalKB)) found")
        log("Estimated recoverable (DerivedData) : \(Format.human(derivedSizeKB))")
        log("Estimated combined recoverable      : \(Format.human(scan.removableBuildKB + derivedSizeKB))")
        log("")

        var clean = CleanSummary()
        var derivedRemoved = DerivedDataCleanSummary()
        var archivePath: String?

        if config.doClean, !scan.containers.isEmpty {
            log("==============================================")
            log("  Xcode Clean")
            log("==============================================")
            onStep?("Running xcodebuild clean…")
            clean = CleanupService.runXcodeClean(containers: scan.containers, log: log)
            warnings += clean.failures
            log("  Cleaned: \(clean.success), Failed: \(clean.failed), Skipped: \(clean.skipped)")
            log("")
        } else {
            log("Xcode clean: skipped.")
        }

        if cancelled() { return finish(scan: scan, clean: clean, archivePath: nil, timestamp: timestamp, startedAt: startedAt, cancelled: true, reportOK: false) }

        if config.doDerivedData, !derivedFolders.isEmpty {
            log("==============================================")
            log("  DerivedData Cleanup")
            log("==============================================")
            onStep?("Removing DerivedData…")
            derivedRemoved = CleanupService.removeDerivedData(paths: derivedFolders, log: log)
            warnings += derivedRemoved.failures
            log("  Removed: \(Format.human(derivedRemoved.removedKB)), Failed: \(derivedRemoved.failed)")
            log("")
        } else {
            log("DerivedData cleanup: skipped.")
        }

        if cancelled() { return finish(scan: scan, clean: clean, archivePath: nil, timestamp: timestamp, startedAt: startedAt, cancelled: true, reportOK: false) }

        var buildRemoved = BuildCleanSummary()
        if config.doRemoveBuildFolders, !scan.buildFolders.isEmpty {
            log("==============================================")
            log(config.dryRunCleanup ? "  Build Folder Cleanup (preview, nothing deleted)" : "  Build Folder Cleanup")
            log("==============================================")
            onStep?(config.dryRunCleanup ? "Listing build folders…" : "Removing build folders…")
            buildRemoved = CleanupService.removeBuildFolders(
                scan.buildFolders,
                searchRoot: searchRoot,
                dryRun: config.dryRunCleanup,
                log: log
            )
            warnings += buildRemoved.failures
            let verb = config.dryRunCleanup ? "Would remove" : "Removed"
            log("  \(verb): \(buildRemoved.removed) folder(s), \(Format.human(buildRemoved.removedKB)); skipped \(buildRemoved.skipped); failed \(buildRemoved.failed)")
            log("")
        } else {
            log("Build folder cleanup: skipped.")
        }

        if cancelled() { return finish(scan: scan, clean: clean, archivePath: nil, timestamp: timestamp, startedAt: startedAt, cancelled: true, reportOK: false) }

        if config.previewArchive {
            onStep?("Working out what would be archived…")
            previewSummary = makePreview(
                scan: scan,
                derivedFolders: derivedFolders,
                derivedSizeKB: derivedSizeKB,
                searchRoot: searchRoot,
                startedAt: startedAt,
                log: log
            )
            if cancelled() { return finish(scan: scan, clean: clean, archivePath: nil, timestamp: timestamp, startedAt: startedAt, cancelled: true, reportOK: false) }
        }

        if config.doArchive {
            log("==============================================")
            log("  Archive Projects Folder")
            log("==============================================")
            onStep?("Creating the zip archive…")
            let zipPath = resolveZipPath(zipPathSetting: config.zipPath, searchRoot: searchRoot, slug: slug, timestamp: timestamp)
            let password = resolvePassword()
            let hasPassword = !(password ?? "").isEmpty
            let excludeSecrets = config.excludeSecretsAlways || !hasPassword
            if excludeSecrets {
                log("Credential files (signing.env, .sentryclirc, .env, .p12 …) will be left out of the archive.")
            }
            if hasPassword {
                log("Note: zip's built-in encryption (ZipCrypto) is weak and the password is visible to other local processes while zip runs. Keep the archive on trusted storage.")
            }
            let exclusions = archiveExclusions(scan: scan, excludeSecrets: excludeSecrets)
            if config.passwordMode != .none, password == nil {
                let modeLabel = config.passwordMode == .keychain ? "Keychain" : "Custom"
                log("✗ No zip password available (\(modeLabel) mode). Open Settings and save a password — archive skipped.")
                archiveFailed = true
                warnings.append("The archive was skipped: no zip password is saved for \(modeLabel) mode.")
            } else {
                log("Archiving \(searchRoot) to \(zipPath)...")
                let handle = ProcessHandle()
                activeHandle = handle
                if ArchiveService.makeArchive(
                    searchRoot: searchRoot,
                    zipPath: zipPath,
                    password: password,
                    exclusions: exclusions,
                    handle: handle,
                    log: log
                ) {
                    archivePath = zipPath
                } else {
                    archiveFailed = true
                    warnings.append("The zip archive could not be created. See the log above for zip's message.")
                }
                activeHandle = nil
            }
        } else {
            log("Archive: skipped.")
        }

        if !warnings.isEmpty {
            log("")
            log("==============================================")
            log("  WARNINGS (\(warnings.count))")
            log("==============================================")
            for (index, warning) in warnings.enumerated() {
                log("  \(index + 1). \(warning)")
            }
        }

        let reportFiles = ReportService.write(
            searchRoot: searchRoot,
            reportDir: reportDir,
            timestamp: timestamp,
            alias: config.reportAlias,
            folderSlug: slug,
            scan: scan,
            derivedDataFolders: derivedFolders,
            derivedDataSizeKB: derivedSizeKB,
            clean: clean,
            derivedRemoved: derivedRemoved,
            buildRemoved: buildRemoved,
            dryRun: config.dryRunCleanup,
            warnings: warnings,
            archive: archivePath
        )
        let reportOK = reportFiles != nil
        failureCount = clean.failed + derivedRemoved.failed + buildRemoved.failed
        if let reportFiles {
            log("")
            log("Report saved : \(reportFiles.txtPath)")
            log("CSV saved    : \(reportFiles.csvPath)")
        } else {
            log("")
            log("✗ Could not write reports to \(reportDir)")
        }

        log("")
        log("==============================================")
        log("  All done!")
        log("==============================================")

        return finish(scan: scan, clean: clean, archivePath: archivePath, timestamp: timestamp, startedAt: startedAt, cancelled: false, reportOK: reportOK)
    }

    /// The exact -x list the real archive uses, so a preview matches a run.
    private func archiveExclusions(scan: ScanResult, excludeSecrets: Bool) -> [String] {
        let artifactPaths = scan.buildFolders.filter { $0.kind == .xcodeBuild && !$0.hasTrackedFiles }.map(\.path)
        return ArchiveService.effectiveExclusions(
            userPatterns: config.exclusions,
            artifactPaths: artifactPaths,
            excludeSecrets: excludeSecrets
        )
    }

    private func makePreview(
        scan: ScanResult,
        derivedFolders: [String],
        derivedSizeKB: Int,
        searchRoot: String,
        startedAt: Date,
        log: (String) -> Void
    ) -> PreviewSummary {
        var summary = PreviewSummary(searchRoot: searchRoot)
        summary.projectsScanned = scan.containers.count
        summary.schemesSeen = scan.totalSchemes
        summary.buildFolders = scan.buildFolders
        summary.derivedDataFolders = derivedFolders.count
        summary.derivedDataKB = derivedSizeKB
        summary.archiveSettingOn = config.archiveToggleOn

        let password = resolvePassword()
        let hasPassword = !(password ?? "").isEmpty
        let excludeSecrets = config.excludeSecretsAlways || !hasPassword
        summary.archiveEncrypted = hasPassword
        summary.credentialFilesLeftOut = excludeSecrets
        let exclusions = archiveExclusions(scan: scan, excludeSecrets: excludeSecrets)

        log("==============================================")
        log("  Archive Preview (nothing is zipped)")
        log("==============================================")
        let handle = ProcessHandle()
        activeHandle = handle
        let included = ArchiveService.dryRunListing(searchRoot: searchRoot, exclusions: exclusions, handle: handle)
        if let included, !isCancelled {
            summary.archiveFiles = included.files.count
            summary.archiveBytes = included.bytes
            log("Would archive \(included.files.count) file(s), about \(Format.humanBytes(included.bytes)) before compression.")

            if let everything = ArchiveService.dryRunListing(searchRoot: searchRoot, exclusions: [], handle: handle), !isCancelled {
                let keep = Set(included.files)
                let leftOut = everything.files.filter { !keep.contains($0) }
                summary.excludedFiles = leftOut.count
                summary.excludedByRule = ArchiveService.countByRule(excluded: leftOut, patterns: exclusions)
                log("Would leave out \(leftOut.count) file(s).")
                for rule in summary.excludedByRule.prefix(8) {
                    log("  \(rule.count)  \(rule.pattern)")
                }
            }

            // zip counts a sparse file at its full reported size, so a huge total
            // against little disk use means one is being read.
            let usedKB = ProjectScanner.diskUsageKB(at: searchRoot) - scan.removableBuildKB
            if included.bytes > 8 * 1_073_741_824, included.bytes / 1024 > Int64(max(usedKB, 1)) * 4 {
                summary.warnings.append("The archive reports \(Format.humanBytes(included.bytes)) but the folder uses far less on disk. A very large sparse file may be included, which would make zip slow.")
            }
        } else {
            log("Could not list what would be archived.")
            summary.warnings.append("The archive preview could not be worked out. Run Scan Only or check the log.")
        }
        activeHandle = nil

        if !config.archiveToggleOn {
            summary.warnings.append("Create zip archive is off in Settings, so a run would not zip anything. The figures show what it would zip if it were on.")
        }
        if !summary.archiveEncrypted, config.passwordMode != .none {
            summary.warnings.append("No zip password is saved for \(config.passwordMode == .keychain ? "Keychain" : "Custom") mode, so the archive would be skipped. Open Settings to save one.")
        } else if !summary.archiveEncrypted {
            summary.warnings.append("The archive would be unencrypted. Credential files are left out automatically.")
        }
        summary.removalSettingOn = config.removeToggleOn
        summary.derivedSettingOn = config.derivedToggleOn
        summary.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
        return summary
    }

    private func finish(
        scan: ScanResult,
        clean: CleanSummary,
        archivePath: String?,
        timestamp: String,
        startedAt: Date,
        cancelled: Bool,
        reportOK: Bool
    ) -> String {
        let summary = summaryLine(scan: scan, clean: clean, archivePath: archivePath, timestamp: timestamp, cancelled: cancelled)
        if cancelled {
            outcome = .cancelled
        } else if !reportOK || archiveFailed {
            outcome = .error
        } else if failureCount > 0 {
            outcome = .warnings
        } else {
            outcome = .ok
        }
        let status: String
        if cancelled {
            status = "CANCELLED"
        } else if !reportOK || archiveFailed {
            status = "ERROR"
        } else if !warnings.isEmpty {
            status = "WARN"
        } else {
            status = "OK"
        }
        RunLogService.record(
            start: startedAt,
            end: Date(),
            status: status,
            mode: config.scheduleMode.rawValue,
            details: summary
        )
        return summary
    }

    private func cancelled() -> Bool {
        if isCancelled {
            logHandler?("")
            logHandler?("Run cancelled.")
        }
        return isCancelled
    }

    private var logHandler: ((String) -> Void)?

    private func resolvePassword() -> String? {
        switch config.passwordMode {
        case .none:
            return nil
        case .keychain:
            return KeychainService.getPassword(account: KeychainAccount.zipPassword)
        case .custom:
            return KeychainService.getPassword(account: KeychainAccount.customPassword)
        }
    }

    private func resolveZipPath(zipPathSetting: String, searchRoot: String, slug: String, timestamp: String) -> String {
        let filename = ArchiveService.defaultZipFilename(folderSlug: slug, timestamp: timestamp)
        let setting = zipPathSetting.trimmingCharacters(in: .whitespaces).isEmpty ? "~/Downloads" : zipPathSetting
        let expanded = setting.expandingTilde()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return (expanded as NSString).appendingPathComponent(filename)
        }
        if expanded.hasSuffix("/") {
            return (expanded as NSString).appendingPathComponent(filename)
        }
        return expanded
    }

    private func summaryLine(scan: ScanResult, clean: CleanSummary, archivePath: String?, timestamp: String, cancelled: Bool) -> String {
        if cancelled {
            return "Cancelled at \(timestamp) — \(scan.containers.count) project(s) scanned"
        }
        var parts = ["\(scan.containers.count) project(s)", "\(clean.success) cleaned"]
        if !warnings.isEmpty {
            parts.append("\(warnings.count) warning(s)")
        }
        if let archivePath {
            let size = ProjectScanner.diskUsageKB(at: archivePath)
            parts.append("archive \(Format.human(size))")
        }
        return "Ran \(timestamp) — \(parts.joined(separator: ", "))"
    }
}
