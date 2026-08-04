import Foundation

enum ArchiveService {
    static let defaultExclusions: [String] = [
        "*.DS_Store",
        "*/__MACOSX/*",
        "*/.build/*",
        "*/DerivedData/*",
        "*/Library/Developer/Xcode/DerivedData/*",
        "*/xcuserdata/*",
        "*/Pods/*",
        "*/Carthage/Build/*",
        "*/.swiftpm/*",
        "*/SourcePackages/*",
        "*/Index.noindex/*",
        "*/ModuleCache.noindex/*",
        "*/Build/Intermediates.noindex/*",
        "*/Build/Products/*",
        "*/Logs/Build/*",
        "*/*.dSYM/*",
        "*/*.app/*",
        "*/node_modules/*"
    ]

    static func defaultZipFilename(folderSlug: String, timestamp: String) -> String {
        "\(folderSlug)_\(timestamp).zip"
    }

    static func makeArchive(
        searchRoot: String,
        zipPath: String,
        password: String?,
        exclusions: [String],
        handle: ProcessHandle,
        log: (String) -> Void
    ) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: zipPath) {
            try? fileManager.removeItem(atPath: zipPath)
        }

        var args: [String] = ["-r"]
        if let password, !password.isEmpty {
            args += ["-P", password]
        }
        args += [zipPath, searchRoot]
        if !exclusions.isEmpty {
            args += ["-x"] + exclusions
        }

        log("Running: zip -r \(password != nil ? "(encrypted) " : "")\(zipPath) \(searchRoot) (\(exclusions.count) exclusions)")
        let result = ProcessRunner.run(
            executable: "/usr/bin/zip",
            arguments: args,
            handle: handle
        )
        if result.succeeded {
            let size = ProjectScanner.diskUsageKB(at: zipPath)
            log("  ✓ Archive created: \(zipPath) (\(Format.human(size)))")
            return true
        } else {
            log("  ✗ zip failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            return false
        }
    }
}
