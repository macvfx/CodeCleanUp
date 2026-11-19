import Foundation

struct ReportFiles {
    let txtPath: String
    let csvPath: String
}

enum ReportService {
    static func reportBaseName(alias: String, folderSlug: String, timestamp: String) -> String {
        var parts: [String] = []
        let cleanAlias = sanitize(alias)
        if !cleanAlias.isEmpty {
            parts.append(cleanAlias)
        }
        if !folderSlug.isEmpty {
            parts.append(folderSlug)
        }
        parts.append(timestamp)
        return parts.joined(separator: "_")
    }

    private static func sanitize(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let runs = text.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return runs.joined(separator: "_")
    }

    static func write(
        searchRoot: String,
        reportDir: String,
        timestamp: String,
        alias: String,
        folderSlug: String,
        scan: ScanResult,
        derivedDataFolders: [String],
        derivedDataSizeKB: Int,
        clean: CleanSummary,
        derivedRemoved: DerivedDataCleanSummary,
        buildRemoved: BuildCleanSummary,
        dryRun: Bool,
        archive: String?
    ) -> ReportFiles? {
        let dir = reportDir.expandingTilde()
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let baseName = reportBaseName(alias: alias, folderSlug: folderSlug, timestamp: timestamp)
        let txtPath = "\(dir)/\(baseName).txt"
        let csvPath = "\(dir)/\(baseName).csv"

        var lines: [String] = []
        lines.append("Xcode Containers Report")
        lines.append("Generated : \(Date())")
        lines.append("Root      : \(searchRoot)")
        lines.append("========================================")
        lines.append("")
        for container in scan.containers {
            lines.append("Type:   \(container.kind)")
            lines.append("Path:   \(container.path)")
            lines.append("Parent: \(container.parent)")
            lines.append("Schemes: \(!container.schemesChecked ? "(not checked)" : container.schemes.isEmpty ? "(none detected)" : container.schemes.joined(separator: "; "))")
            lines.append("")
        }
        if !scan.buildFolders.isEmpty {
            lines.append("Build folders")
            for folder in scan.buildFolders {
                let note = folder.skipReason.map { " [kept: \($0)]" } ?? ""
                lines.append("  \(Format.human(folder.sizeKB))  \(folder.kind.rawValue)  \(folder.path)\(note)")
            }
            lines.append("")
        }
        lines.append("----------------------------------------")
        lines.append("  Containers          : \(scan.containers.count)")
        lines.append("  Schemes seen        : \(scan.totalSchemes)")
        lines.append("  Build folders       : \(scan.buildFolders.count) (.build and Xcode build output)")
        lines.append("  Build folder size   : \(Format.human(scan.buildTotalKB))")
        lines.append("  Removable           : \(Format.human(scan.removableBuildKB))")
        lines.append("  DerivedData folders : \(derivedDataFolders.count)")
        lines.append("  DerivedData size    : \(Format.human(derivedDataSizeKB))")
        lines.append("  Recoverable (combined) : \(Format.human(scan.removableBuildKB + derivedDataSizeKB))")
        lines.append("  Cleaned schemes     : \(clean.success)")
        lines.append("  Clean failures      : \(clean.failed)")
        lines.append("  DerivedData removed : \(Format.human(derivedRemoved.removedKB))")
        lines.append("  Build folders \(dryRun ? "would remove" : "removed") : \(buildRemoved.removed) (\(Format.human(buildRemoved.removedKB))), skipped \(buildRemoved.skipped)")
        if let archive {
            lines.append("  Archive             : \(archive)")
        }
        lines.append("  Scanned             : \(Date())")
        lines.append("----------------------------------------")

        var csvLines: [String] = []
        csvLines.append("Type,Container,Parent_Folder,Scheme_Count,Schemes")
        for container in scan.containers {
            let schemes = container.schemes.joined(separator: "; ").replacingOccurrences(of: "\"", with: "\"\"")
            csvLines.append("\"\(container.kind)\",\"\(container.path)\",\"\(container.parent)\",\(container.schemes.count),\"\(schemes)\"")
        }
        csvLines.append("")
        csvLines.append("\"TOTAL\",\"\(scan.containers.count) containers\",\"\",\(scan.totalSchemes),\"\"")

        do {
            try lines.joined(separator: "\n").write(toFile: txtPath, atomically: true, encoding: .utf8)
            try csvLines.joined(separator: "\n").write(toFile: csvPath, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }

        return ReportFiles(txtPath: txtPath, csvPath: csvPath)
    }
}
