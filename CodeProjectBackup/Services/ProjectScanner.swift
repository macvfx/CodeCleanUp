import Foundation

struct XcodeContainer {
    let path: String
    let kind: String
    let parent: String
    let schemes: [String]
    /// False when scheme detection was skipped (it runs `xcodebuild -list`, which is slow).
    var schemesChecked = true

    var baseName: String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

enum BuildFolderKind: String {
    case swiftPM = "SwiftPM .build"
    case xcodeBuild = "Xcode build output"
}

struct BuildFolder {
    let path: String
    let sizeKB: Int
    var kind: BuildFolderKind = .swiftPM
    /// Git tracks at least one file inside it, so it is source, not build output.
    var hasTrackedFiles = false
    /// Modified recently enough that a build may still be using it.
    var isRecent = false

    /// Safe to delete: regenerable output only.
    var isRemovable: Bool { !hasTrackedFiles && !isRecent }
    var skipReason: String? {
        if hasTrackedFiles { return "contains git-tracked files" }
        if isRecent { return "modified in the last hour" }
        return nil
    }
}

struct ScanResult {
    let containers: [XcodeContainer]
    let buildFolders: [BuildFolder]

    var buildTotalKB: Int { buildFolders.reduce(0) { $0 + $1.sizeKB } }
    var removableBuildFolders: [BuildFolder] { buildFolders.filter(\.isRemovable) }
    var removableBuildKB: Int { removableBuildFolders.reduce(0) { $0 + $1.sizeKB } }
    var totalSchemes: Int { containers.reduce(0) { $0 + $1.schemes.count } }
    var uniqueBaseNames: Set<String> { Set(containers.map(\.baseName)) }
}

enum ProjectScanner {
    static let derivedDataRoot = ("~/Library/Developer/Xcode/DerivedData" as NSString).expandingTildeInPath

    static func diskUsageKB(at path: String) -> Int {
        let result = ProcessRunner.run(executable: "/usr/bin/du", arguments: ["-sk", path])
        let firstLine = result.stdout.split(separator: "\n").first ?? ""
        let kb = firstLine.split(separator: "\t").first.flatMap { Int($0) } ?? 0
        return kb
    }

    static func scan(searchRoot: String, prunePaths: [String], detectSchemes shouldDetectSchemes: Bool = true, log: (String) -> Void) -> ScanResult {
        let root = searchRoot.expandingTilde()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root) else {
            log("✗ Search root does not exist: \(root)")
            return ScanResult(containers: [], buildFolders: [])
        }

        var containers: [XcodeContainer] = []
        var buildFolders: [BuildFolder] = []
        let pruned = prunePaths.map { $0.expandingTilde() }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return ScanResult(containers: [], buildFolders: [])
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDir = values.isDirectory, isDir else { continue }

            let path = url.path

            if isPruned(path: path, prunePaths: pruned) {
                enumerator.skipDescendants()
                continue
            }

            let name = url.lastPathComponent
            if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
                let kind = name.hasSuffix(".xcworkspace") ? "workspace" : "project"
                let schemes = shouldDetectSchemes ? detectSchemes(kind: kind, path: path) : []
                containers.append(
                    XcodeContainer(
                        path: path,
                        kind: kind,
                        parent: url.deletingLastPathComponent().lastPathComponent,
                        schemes: schemes,
                        schemesChecked: shouldDetectSchemes
                    )
                )
                enumerator.skipDescendants()
                continue
            }

            if name == ".git" || name == "node_modules" {
                enumerator.skipDescendants()
                continue
            }

            if name == ".build" {
                buildFolders.append(makeBuildFolder(path: path, kind: .swiftPM))
                enumerator.skipDescendants()
                continue
            }

            if path != root, isXcodeBuildRoot(path: path, fileManager: fileManager) {
                buildFolders.append(makeBuildFolder(path: path, kind: .xcodeBuild))
                enumerator.skipDescendants()
                continue
            }
        }

        let preferred = preferWorkspaces(containers: containers).sorted { $0.path < $1.path }
        return ScanResult(
            containers: preferred,
            buildFolders: buildFolders.sorted { $0.path < $1.path }
        )
    }

    /// A directory is Xcode build output (a DerivedData-style root) when it holds
    /// one of these markers. Detected by content, not by name, so folders such as
    /// `Build`, `BuildPortFix` or `build` are found, and a source folder that only
    /// shares the name is not.
    static let buildRootMarkers: [String] = [
        "Build/Products",
        "Build/Intermediates.noindex",
        "CompilationCache.noindex",
        "SwiftExplicitPrecompiledModules",
        "SDKExplicitPrecompiledModules",
        "SDKStatCaches.noindex",
        "XCBuildData",
        "Index.noindex",
        "ModuleCache.noindex",
        "ModuleCache"
    ]

    static func isXcodeBuildRoot(path: String, fileManager: FileManager) -> Bool {
        for marker in buildRootMarkers {
            var isDir: ObjCBool = false
            let candidate = (path as NSString).appendingPathComponent(marker)
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return true
            }
        }
        return false
    }

    static func makeBuildFolder(path: String, kind: BuildFolderKind) -> BuildFolder {
        var folder = BuildFolder(path: path, sizeKB: diskUsageKB(at: path), kind: kind)
        folder.hasTrackedFiles = hasGitTrackedFiles(at: path)
        if let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
            folder.isRecent = Date().timeIntervalSince(modified) < 3600
        }
        return folder
    }

    /// True when git tracks any file under `path`. A folder outside any repo is untracked.
    static func hasGitTrackedFiles(at path: String) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let result = ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", parent, "ls-files", "--", name]
        )
        guard result.succeeded else { return false }
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func detectSchemes(kind: String, path: String) -> [String] {
        let flag = kind == "workspace" ? "-workspace" : "-project"
        let result = ProcessRunner.run(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-list", flag, path]
        )
        guard result.succeeded else { return [] }
        return parseSchemes(from: result.stdout)
    }

    static func parseSchemes(from output: String) -> [String] {
        var schemes: [String] = []
        var inSchemes = false
        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inSchemes {
                if trimmed.isEmpty { continue }
                if line.hasPrefix(" ") || line.hasPrefix("\t") {
                    schemes.append(trimmed)
                } else {
                    break
                }
            } else if trimmed.hasPrefix("Schemes:") {
                inSchemes = true
            }
        }
        return schemes
    }

    static func findDerivedDataFolders(bases: Set<String>) -> [String] {
        guard FileManager.default.fileExists(atPath: derivedDataRoot) else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: derivedDataRoot) else { return [] }
        var result = Set<String>()
        for base in bases {
            let variants = Set([
                base,
                base.replacingOccurrences(of: " ", with: ""),
                base.replacingOccurrences(of: " ", with: "_")
            ])
            for entry in entries {
                for variant in variants where entry.hasPrefix(variant + "-") {
                    result.insert((derivedDataRoot as NSString).appendingPathComponent(entry))
                }
            }
        }
        return result.sorted()
    }

    private static func isPruned(path: String, prunePaths: [String]) -> Bool {
        for prune in prunePaths where !prune.isEmpty {
            if path == prune || path.hasPrefix(prune + "/") {
                return true
            }
        }
        return false
    }

    private static func preferWorkspaces(containers: [XcodeContainer]) -> [XcodeContainer] {
        var dirHasWorkspace = Set<String>()
        for container in containers where container.kind == "workspace" {
            dirHasWorkspace.insert((container.path as NSString).deletingLastPathComponent)
        }
        return containers.filter { container in
            if container.kind == "project" {
                let dir = (container.path as NSString).deletingLastPathComponent
                if dirHasWorkspace.contains(dir) { return false }
            }
            return true
        }
    }
}
