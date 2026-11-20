import AppKit
import Foundation

/// What the optional "developer tools" cleanup is allowed to touch.
struct DevToolsOptions {
    var archives = true
    var archiveDays = 60
    var deviceSupport = true
    var caches = true
    var simulators = true
}

enum DevToolsKind: String {
    case archive = "Xcode archive"
    case deviceSupport = "Device support"
    case cache = "Cache"
}

struct DevToolsCandidate {
    let path: String
    let kind: DevToolsKind
    let sizeKB: Int
}

struct DevToolsPlan {
    var candidates: [DevToolsCandidate] = []
    /// Simulator devices Xcode already marks unavailable.
    var unavailableSimulators = 0
    /// Why a category was left alone, one readable line each.
    var notes: [String] = []

    var totalKB: Int { candidates.reduce(0) { $0 + $1.sizeKB } }
}

struct DevToolsCleanSummary {
    var trashed = 0
    var trashedKB = 0
    var failed = 0
    var simulatorsDeleted = 0
    var failures: [String] = []
}

/// Reclaims space used by Xcode and developer tools, outside the projects folder:
/// old archives, old device-support symbols, Xcode and SwiftPM caches, unavailable
/// simulators. Everything goes to the Trash so it can be put back; the rules match
/// `dev_space_cleanup.sh` in the find repo.
enum DevToolsCleanupService {
    private static var home: String { NSHomeDirectory() }
    private static var xcodeSupport: String { home + "/Library/Developer/Xcode" }
    private static var archivesRoot: String { xcodeSupport + "/Archives" }

    /// The only places this service will ever remove from (archives, device-support
    /// folders and three cache locations; never DerivedData, projects or source).
    private static var allowedRoots: [String] {
        [archivesRoot,
         home + "/Library/Caches/com.apple.dt.Xcode",
         home + "/Library/Caches/org.swift.swiftpm",
         home + "/Library/Logs/CoreSimulator"]
    }

    private static func isDeviceSupportPath(_ path: String) -> Bool {
        let prefix = xcodeSupport + "/"
        guard path.hasPrefix(prefix) else { return false }
        let parts = path.dropFirst(prefix.count).split(separator: "/")
        return parts.count >= 2 && parts[0].hasSuffix(" DeviceSupport")
    }

    // MARK: Planning (read-only)

    static func plan(options: DevToolsOptions, log: (String) -> Void) -> DevToolsPlan {
        var plan = DevToolsPlan()
        let fm = FileManager.default

        if options.archives {
            for path in staleArchives(days: options.archiveDays) {
                plan.candidates.append(DevToolsCandidate(path: path, kind: .archive, sizeKB: ProjectScanner.diskUsageKB(at: path)))
            }
        }
        if options.deviceSupport {
            for path in staleDeviceSupport() {
                plan.candidates.append(DevToolsCandidate(path: path, kind: .deviceSupport, sizeKB: ProjectScanner.diskUsageKB(at: path)))
            }
        }
        if options.caches {
            if xcodeIsRunning {
                plan.notes.append("Xcode and SwiftPM caches were not checked because Xcode is open. Close Xcode and run Preview again to include them.")
            } else {
                for path in [home + "/Library/Caches/com.apple.dt.Xcode",
                             home + "/Library/Caches/org.swift.swiftpm",
                             home + "/Library/Logs/CoreSimulator"] where fm.fileExists(atPath: path) {
                    plan.candidates.append(DevToolsCandidate(path: path, kind: .cache, sizeKB: ProjectScanner.diskUsageKB(at: path)))
                }
            }
        }
        if options.simulators {
            plan.unavailableSimulators = unavailableSimulatorCount()
        }
        return plan
    }

    /// Archives in folders older than `days`, except the newest archive of each app.
    /// An archive holds the only dSYMs for that build, so the latest is always kept.
    static func staleArchives(days: Int) -> [String] {
        let fm = FileManager.default
        guard let dayFolders = try? fm.contentsOfDirectory(atPath: archivesRoot) else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(days, 1), to: Date()) ?? Date()
        let cutoffName = dayFormatter.string(from: cutoff)
        let datePattern = try! NSRegularExpression(pattern: #"^\d{4}-\d\d-\d\d$"#)

        struct Item { let app: String; let day: String; let path: String; let modified: Date }
        var items: [Item] = []
        for day in dayFolders.sorted() {
            let range = NSRange(day.startIndex..., in: day)
            guard datePattern.firstMatch(in: day, range: range) != nil else { continue }
            let dayPath = archivesRoot + "/" + day
            guard let entries = try? fm.contentsOfDirectory(atPath: dayPath) else { continue }
            for entry in entries where entry.hasSuffix(".xcarchive") {
                let path = dayPath + "/" + entry
                let modified = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                items.append(Item(app: appName(fromArchive: entry), day: day, path: path, modified: modified))
            }
        }
        var newest: [String: Item] = [:]
        for item in items {
            if let current = newest[item.app], (current.day, current.modified) >= (item.day, item.modified) { continue }
            newest[item.app] = item
        }
        let keep = Set(newest.values.map(\.path))
        return items.filter { $0.day < cutoffName && !keep.contains($0.path) }.map(\.path)
    }

    /// "CopyTrust-3.0.6-b80.xcarchive" and "CopyTrust 2026-11-18, 17.44.xcarchive" are both "CopyTrust".
    static func appName(fromArchive file: String) -> String {
        var name = String(file.dropLast(".xcarchive".count))
        if let r = name.range(of: #" \d{4}-\d\d-\d\d.*"#, options: .regularExpression) { name.removeSubrange(r) }
        if let r = name.range(of: #"-\d.*"#, options: .regularExpression) { name.removeSubrange(r) }
        return name
    }

    /// Old OS versions of device symbols, keeping the newest per device model.
    /// Xcode rebuilds one the next time that device is connected.
    static func staleDeviceSupport() -> [String] {
        let fm = FileManager.default
        guard let platforms = try? fm.contentsOfDirectory(atPath: xcodeSupport) else { return [] }
        let pattern = try! NSRegularExpression(pattern: #"^(\S+) (\S+) \("#)
        var stale: [String] = []
        for platform in platforms.sorted() where platform.hasSuffix(" DeviceSupport") {
            let platformPath = xcodeSupport + "/" + platform
            guard let entries = try? fm.contentsOfDirectory(atPath: platformPath) else { continue }
            var byModel: [String: [(version: [Int], path: String)]] = [:]
            for entry in entries {
                let range = NSRange(entry.startIndex..., in: entry)
                guard let match = pattern.firstMatch(in: entry, range: range),
                      let modelRange = Range(match.range(at: 1), in: entry),
                      let versionRange = Range(match.range(at: 2), in: entry) else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: platformPath + "/" + entry, isDirectory: &isDir), isDir.boolValue else { continue }
                let version = entry[versionRange].split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
                byModel[String(entry[modelRange]), default: []].append((version, platformPath + "/" + entry))
            }
            for (_, group) in byModel {
                let sorted = group.sorted { $0.version.lexicographicallyPrecedes($1.version) }
                stale += sorted.dropLast().map(\.path)
            }
        }
        return stale.sorted()
    }

    static var xcodeIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty
    }

    static func unavailableSimulatorCount() -> Int {
        let result = ProcessRunner.run(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "devices"])
        guard result.succeeded else { return 0 }
        return result.stdout.split(separator: "\n").filter { $0.contains("(unavailable") }.count
    }

    // MARK: Cleaning

    static func clean(plan: DevToolsPlan, dryRun: Bool, log: (String) -> Void) -> DevToolsCleanSummary {
        var summary = DevToolsCleanSummary()
        let fm = FileManager.default
        for item in plan.candidates {
            guard isAllowed(item.path) else {
                summary.failed += 1
                summary.failures.append("Refused to remove a path outside the Xcode folders: \(item.path)")
                log("  ✗ Refused (outside the Xcode folders): \(item.path)")
                continue
            }
            if dryRun {
                log("  would trash \(Format.human(item.sizeKB)) [\(item.kind.rawValue)] — \(item.path)")
                summary.trashed += 1
                summary.trashedKB += item.sizeKB
                continue
            }
            do {
                try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: nil)
                summary.trashed += 1
                summary.trashedKB += item.sizeKB
                log("  ✓ Trashed \(Format.human(item.sizeKB)) [\(item.kind.rawValue)] — \(item.path)")
            } catch {
                summary.failed += 1
                summary.failures.append("Could not move \(item.path) to the Trash: \(error.localizedDescription)")
                log("  ✗ Failed: \(item.path): \(error.localizedDescription)")
            }
        }
        if plan.unavailableSimulators > 0 {
            if dryRun {
                log("  would delete \(plan.unavailableSimulators) unavailable simulator device(s)")
            } else {
                let result = ProcessRunner.run(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"])
                if result.succeeded {
                    summary.simulatorsDeleted = plan.unavailableSimulators
                    log("  ✓ Deleted \(plan.unavailableSimulators) unavailable simulator device(s)")
                } else {
                    summary.failed += 1
                    summary.failures.append("simctl could not delete unavailable simulators: \(CleanupService.failureReason(result))")
                    log("  ✗ simctl delete unavailable failed: \(CleanupService.failureReason(result))")
                }
            }
        }
        return summary
    }

    private static func isAllowed(_ path: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        guard !standardized.contains("/../") else { return false }
        if isDeviceSupportPath(standardized) { return true }
        return allowedRoots.contains { standardized == $0 || standardized.hasPrefix($0 + "/") }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
