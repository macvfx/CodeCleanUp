import Foundation

enum RunLogService {
    static var logDirectory: String {
        ("~/Library/Logs/CodeProjectBackup" as NSString).expandingTildeInPath
    }

    static var logPath: String {
        (logDirectory as NSString).appendingPathComponent("runs.log")
    }

    /// One full log per run lives here, newest kept (see `keepRunLogs`).
    static var runLogsDirectory: String {
        (logDirectory as NSString).appendingPathComponent("runs")
    }
    private static let keepRunLogs = 40

    /// Writes a run's complete log and returns its path. Older logs beyond the newest
    /// `keepRunLogs` are removed so the folder cannot grow without limit.
    static func saveRunLog(text: String, kind: String, date: Date) -> String? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: runLogsDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let name = "\(Format.timestamp.string(from: date))-\(kind).log"
        let path = (runLogsDirectory as NSString).appendingPathComponent(name)
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        let all = recentRunLogs()
        for old in all.dropFirst(keepRunLogs) {
            try? fileManager.removeItem(at: old)
        }
        return path
    }

    /// Saved run logs, newest first.
    static func recentRunLogs() -> [URL] {
        let url = URL(fileURLWithPath: runLogsDirectory, isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static let lock = NSLock()
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter
    }()

    static func record(start: Date, end: Date, status: String, mode: String, details: String) {
        lock.lock()
        defer { lock.unlock() }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)
        } catch {
            return
        }

        let startText = dateFormatter.string(from: start)
        let endText = dateFormatter.string(from: end)
        let duration = max(Int(end.timeIntervalSince(start)), 0)
        let detailsText = details.replacingOccurrences(of: "|", with: ";")
        let line = "\(startText) | \(endText) | \(duration)s | \(status) | \(mode) | \(detailsText)\n"
        guard let data = line.data(using: .utf8) else { return }

        if fileManager.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            var header = "start | end | duration | status | mode | details\n"
            if let headerData = header.data(using: .utf8) {
                try? headerData.write(to: URL(fileURLWithPath: logPath), options: [.atomic])
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            }
        }
    }
}
