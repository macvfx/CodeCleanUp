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
        "*/node_modules/*",
        // Xcode 16+ / Swift build caches. CompilationCache.noindex can hold a
        // sparse file that reports tens of GB, which zip would read in full.
        "*/CompilationCache.noindex/*",
        "*/SwiftExplicitPrecompiledModules/*",
        "*/SDKExplicitPrecompiledModules/*",
        "*/SDKStatCaches.noindex/*",
        "*/XCBuildData/*",
        // Agent worktrees and Python environments are rebuildable copies.
        "*/.claude/worktrees/*",
        "*/.venv/*",
        "*/.venv-*/*",
        "*/__pycache__/*"
    ]

    /// Bump when `defaultExclusions` gains patterns, so saved settings pick them up.
    static let exclusionsVersion = 2

    /// Files that hold credentials. Skipped automatically when the archive is not
    /// password-protected, or always when the "always exclude secrets" option is on.
    static let secretExclusions: [String] = [
        "*/signing.env",
        "*/.sentryclirc",
        "*/.env",
        "*/.env.local",
        "*/.env.production",
        "*/*.p12",
        "*/*.mobileprovision",
        "*/id_rsa",
        "*/id_ed25519"
    ]

    /// zip -x patterns treat these as wildcards; a literal path must escape them.
    static func escapeForZip(_ path: String) -> String {
        var out = ""
        for ch in path {
            if "[]?*\\".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Final -x list: the user's list, plus the exact build folders the scan found
    /// (precise, so a source folder that merely shares a name is never dropped),
    /// plus secret patterns when required.
    static func effectiveExclusions(
        userPatterns: [String],
        artifactPaths: [String],
        excludeSecrets: Bool
    ) -> [String] {
        var result = userPatterns
        result += artifactPaths.map { escapeForZip($0) + "/*" }
        if excludeSecrets { result += secretExclusions }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

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
