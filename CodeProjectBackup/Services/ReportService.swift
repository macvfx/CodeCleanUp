import Foundation

struct ReportFiles {
    let txtPath: String
    let csvPath: String
}

enum ReportService {
    static func write(
        searchRoot: String,
        reportDir: String,
        timestamp: String,
        scan: ScanResult,
        derivedDataFolders: [String],
        derivedDataSizeKB: Int,
        clean: CleanSummary,
        derivedRemoved: DerivedDataCleanSummary,
        archive: String?
    ) -> ReportFiles? {
        let dir = reportDir.expandingTilde()
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let txtPath = "\(dir)/xcode_projects_\(timestamp).txt"
        let csvPath = "\(dir)/xcode_projects_\(timestamp).csv"

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
            lines.append("Schemes: \(container.schemes.isEmpty ? "(none detected)" : container.schemes.joined(separator: "; "))")
            lines.append("")
        }
        lines.append("----------------------------------------")
        lines.append("  Containers          : \(scan.containers.count)")
        lines.append("  Schemes seen        : \(scan.totalSchemes)")
        lines.append("  .build dirs         : \(scan.buildFolders.count)")
        lines.append("  .build size         : \(Format.human(scan.buildTotalKB))")
        lines.append("  DerivedData folders : \(derivedDataFolders.count)")
        lines.append("  DerivedData size    : \(Format.human(derivedDataSizeKB))")
        lines.append("  Recoverable (combined) : \(Format.human(scan.buildTotalKB + derivedDataSizeKB))")
        lines.append("  Cleaned schemes     : \(clean.success)")
        lines.append("  Clean failures      : \(clean.failed)")
        lines.append("  DerivedData removed : \(Format.human(derivedRemoved.removedKB))")
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
