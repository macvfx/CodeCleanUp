import Foundation

enum RunLogService {
    static var logDirectory: String {
        ("~/Library/Logs/CodeProjectBackup" as NSString).expandingTildeInPath
    }

    static var logPath: String {
        (logDirectory as NSString).appendingPathComponent("runs.log")
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
