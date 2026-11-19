import Foundation

struct PreviewRuleCount: Identifiable {
    let pattern: String
    let count: Int
    var id: String { pattern }
}

/// What a run would do, worked out without changing anything.
struct PreviewSummary {
    var searchRoot: String
    var generatedAt = Date()
    var elapsedSeconds = 0
    var projectsScanned = 0
    var schemesSeen = 0
    var buildFolders: [BuildFolder] = []
    var derivedDataFolders = 0
    var derivedDataKB = 0

    /// Nil when the archive dry run did not run or failed.
    var archiveFiles: Int?
    var archiveBytes: Int64?
    var excludedFiles: Int?
    var excludedByRule: [PreviewRuleCount] = []
    var archiveEncrypted = false
    var credentialFilesLeftOut = false
    var archiveSettingOn = true
    var removalSettingOn = false
    var derivedSettingOn = true

    var warnings: [String] = []

    var removable: [BuildFolder] { buildFolders.filter(\.isRemovable) }
    var kept: [BuildFolder] { buildFolders.filter { !$0.isRemovable } }
    var removableKB: Int { removable.reduce(0) { $0 + $1.sizeKB } }

    /// Plain-text copy of the summary, for pasting.
    var plainText: String {
        var lines: [String] = []
        lines.append("Code Project Backup preview — nothing was changed")
        lines.append("Folder: \(searchRoot)")
        lines.append("Scanned: \(projectsScanned) Xcode project(s)")
        lines.append("Would remove: \(removable.count) build folder(s), \(Format.human(removableKB))")
        lines.append("Kept: \(kept.count) build folder(s)")
        if derivedDataFolders > 0 {
            lines.append("DerivedData: \(derivedDataFolders) folder(s), \(Format.human(derivedDataKB)), removal \(derivedSettingOn ? "on" : "off") in Settings")
        }
        if let archiveFiles, let archiveBytes {
            lines.append("Archive: \(archiveFiles) file(s), about \(Format.humanBytes(archiveBytes)) before compression")
        }
        if let excludedFiles {
            lines.append("Left out of the archive: \(excludedFiles) file(s)")
            for rule in excludedByRule.prefix(8) {
                lines.append("  \(rule.pattern): \(rule.count)")
            }
        }
        for warning in warnings {
            lines.append("Warning: \(warning)")
        }
        return lines.joined(separator: "\n")
    }
}
