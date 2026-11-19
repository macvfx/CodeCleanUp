import Foundation

struct CleanSummary {
    var success = 0
    var failed = 0
    var skipped = 0
}

struct DerivedDataCleanSummary {
    var removedKB = 0
    var failed = 0
}

struct BuildCleanSummary {
    var removedKB = 0
    var removed = 0
    var skipped = 0
    var failed = 0
}

enum CleanupService {
    /// Deletes regenerable build folders found by the scan. Every path is re-checked
    /// to sit inside `searchRoot`; folders with git-tracked files or recent activity
    /// are skipped and logged. With `dryRun` nothing is deleted.
    static func removeBuildFolders(
        _ folders: [BuildFolder],
        searchRoot: String,
        dryRun: Bool,
        log: (String) -> Void
    ) -> BuildCleanSummary {
        var summary = BuildCleanSummary()
        let root = searchRoot.hasSuffix("/") ? String(searchRoot.dropLast()) : searchRoot
        for folder in folders {
            guard folder.path.hasPrefix(root + "/"), !folder.path.contains("/.git/") else {
                log("  ✗ Refused (outside search root): \(folder.path)")
                summary.failed += 1
                continue
            }
            if let reason = folder.skipReason {
                log("  – Skipped (\(reason)): \(folder.path)")
                summary.skipped += 1
                continue
            }
            if dryRun {
                log("  would remove \(Format.human(folder.sizeKB)) [\(folder.kind.rawValue)] — \(folder.path)")
                summary.removed += 1
                summary.removedKB += folder.sizeKB
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: folder.path)
                summary.removed += 1
                summary.removedKB += folder.sizeKB
                log("  ✓ Removed \(Format.human(folder.sizeKB)) [\(folder.kind.rawValue)] — \(folder.path)")
            } catch {
                summary.failed += 1
                log("  ✗ Failed to remove \(folder.path): \(error.localizedDescription)")
            }
        }
        return summary
    }

    static func runXcodeClean(containers: [XcodeContainer], log: (String) -> Void) -> CleanSummary {
        var summary = CleanSummary()
        for container in containers {
            log("Cleaning \(container.path)")
            guard !container.schemes.isEmpty else {
                log("  No schemes detected — skipping.")
                summary.skipped += 1
                continue
            }
            let flag = container.kind == "workspace" ? "-workspace" : "-project"
            for scheme in container.schemes {
                let result = ProcessRunner.run(
                    executable: "/usr/bin/xcodebuild",
                    arguments: [flag, container.path, "-scheme", scheme, "clean"]
                )
                if result.succeeded {
                    summary.success += 1
                    log("  ✓ \(scheme)")
                } else {
                    summary.failed += 1
                    let detail = result.stderr
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "\n")
                        .last
                        .map(String.init) ?? ""
                    log("  ✗ \(scheme): \(detail.prefix(200))")
                }
            }
        }
        return summary
    }

    static func removeDerivedData(paths: [String], log: (String) -> Void) -> DerivedDataCleanSummary {
        var summary = DerivedDataCleanSummary()
        let fileManager = FileManager.default
        for path in paths {
            let kb = ProjectScanner.diskUsageKB(at: path)
            do {
                try fileManager.removeItem(atPath: path)
                summary.removedKB += kb
                log("  ✓ Removed \(Format.human(kb)) — \(path)")
            } catch {
                summary.failed += 1
                log("  ✗ Failed to remove \(path): \(error.localizedDescription)")
            }
        }
        return summary
    }
}
