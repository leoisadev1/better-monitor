import Foundation

enum MonitorFormatting {
    static func percent(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f%%", value)
        }
        if value >= 10 {
            return String(format: "%.1f%%", value)
        }
        return String(format: "%.2f%%", value)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesActualByteCount = false
        return formatter.string(fromByteCount: value)
    }

    static func rate(_ value: Int64) -> String {
        "\(bytes(value))/s"
    }

    static func rate(_ value: Double) -> String {
        rate(Int64(max(0, value.rounded())))
    }

    static func countRate(_ value: Double) -> String {
        "\(number(Int64(max(0, value.rounded()))))/s"
    }

    static func number(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

extension Double {
    var clampedPercent: Double {
        min(100, max(0, self))
    }
}
