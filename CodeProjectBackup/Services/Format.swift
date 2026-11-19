import Foundation

enum Format {
    static func human(_ kb: Int) -> String {
        let value = Double(kb)
        if value >= 1_048_576 {
            return String(format: "%.1f GB", value / 1_048_576)
        }
        if value >= 1024 {
            return String(format: "%.1f MB", value / 1024)
        }
        return "\(kb) KB"
    }

    static func humanBytes(_ bytes: Int64) -> String {
        human(Int(bytes / 1024))
    }

    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

extension String {
    func expandingTilde() -> String {
        (self as NSString).expandingTildeInPath
    }
}
