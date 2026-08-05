import Foundation

@MainActor
final class RunManager: ObservableObject {
    static let shared = RunManager()

    @Published var isRunning = false
    @Published var logText = ""
    @Published var lastRunSummary: String?

    private var pipeline: PipelineRunner?

    func run(config: RunConfiguration) {
        guard !isRunning else { return }
        isRunning = true
        logText = ""
        lastRunSummary = nil

        let runner = PipelineRunner(config: config)
        pipeline = runner

        Task.detached(priority: .userInitiated) { [weak runner] in
            guard let runner else { return }
            let summary = runner.run { [weak self] message in
                DispatchQueue.main.async {
                    self?.appendLog(message)
                }
            }
            await MainActor.run { [weak self] in
                self?.pipeline = nil
                self?.isRunning = false
                self?.lastRunSummary = summary
            }
        }
    }

    func runScanOnly(config: RunConfiguration) {
        var config = config
        config.doClean = false
        config.doDerivedData = false
        config.doArchive = false
        run(config: config)
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

        let scan = ProjectScanner.scan(searchRoot: searchRoot, prunePaths: config.prunePaths, log: log)
        log("Found \(scan.containers.count) Xcode container(s), \(scan.buildFolders.count) .build folder(s).")
        for container in scan.containers {
            let schemes = container.schemes.isEmpty ? "(no schemes)" : container.schemes.joined(separator: ", ")
            log("  [\(container.kind)] \(container.path)")
            log("    Schemes: \(schemes)")
        }
        for build in scan.buildFolders {
            log("  .build \(Format.human(build.sizeKB)) — \(build.path)")
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
        log("Estimated recoverable (.build)      : \(Format.human(scan.buildTotalKB))")
        log("Estimated recoverable (DerivedData) : \(Format.human(derivedSizeKB))")
        log("Estimated combined recoverable      : \(Format.human(scan.buildTotalKB + derivedSizeKB))")
        log("")

        var clean = CleanSummary()
        var derivedRemoved = DerivedDataCleanSummary()
        var archivePath: String?

        if config.doClean, !scan.containers.isEmpty {
            log("==============================================")
            log("  Xcode Clean")
            log("==============================================")
            clean = CleanupService.runXcodeClean(containers: scan.containers, log: log)
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
            derivedRemoved = CleanupService.removeDerivedData(paths: derivedFolders, log: log)
            log("  Removed: \(Format.human(derivedRemoved.removedKB)), Failed: \(derivedRemoved.failed)")
            log("")
        } else {
            log("DerivedData cleanup: skipped.")
        }

        if cancelled() { return finish(scan: scan, clean: clean, archivePath: nil, timestamp: timestamp, startedAt: startedAt, cancelled: true, reportOK: false) }

        if config.doArchive {
            log("==============================================")
            log("  Archive Projects Folder")
            log("==============================================")
            let zipPath = resolveZipPath(zipPathSetting: config.zipPath, searchRoot: searchRoot, slug: slug, timestamp: timestamp)
            let password = resolvePassword()
            if config.passwordMode != .none, password == nil {
                let modeLabel = config.passwordMode == .keychain ? "Keychain" : "Custom"
                log("✗ No zip password available (\(modeLabel) mode). Open Settings and save a password — archive skipped.")
            } else {
                log("Archiving \(searchRoot) to \(zipPath)...")
                let handle = ProcessHandle()
                activeHandle = handle
                if ArchiveService.makeArchive(
                    searchRoot: searchRoot,
                    zipPath: zipPath,
                    password: password,
                    exclusions: config.exclusions,
                    handle: handle,
                    log: log
                ) {
                    archivePath = zipPath
                }
                activeHandle = nil
            }
        } else {
            log("Archive: skipped.")
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
            archive: archivePath
        )
        let reportOK = reportFiles != nil
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
        let status: String
        if cancelled {
            status = "CANCELLED"
        } else if !reportOK {
            status = "ERROR"
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
        if let archivePath {
            let size = ProjectScanner.diskUsageKB(at: archivePath)
            parts.append("archive \(Format.human(size))")
        }
        return "Ran \(timestamp) — \(parts.joined(separator: ", "))"
    }
}
