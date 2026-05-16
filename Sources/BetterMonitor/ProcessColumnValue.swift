import Foundation

enum ProcessColumnValue {
    static func string(for column: ProcessColumn, process: ProcessSnapshot) -> String {
        switch column {
        case .name:
            return String(repeating: "  ", count: process.hierarchyLevel) + process.name
        case .pid:
            return "\(process.pid)"
        case .user:
            return process.user
        case .cpu:
            return MonitorFormatting.percent(process.cpuPercent)
        case .memory:
            return MonitorFormatting.bytes(process.residentMemoryBytes)
        case .energy:
            return String(format: "%.1f", process.energyImpact)
        case .disk:
            return MonitorFormatting.rate(process.diskReadBytes + process.diskWriteBytes)
        case .diskRead:
            return MonitorFormatting.rate(process.diskReadBytes)
        case .diskWritten:
            return MonitorFormatting.rate(process.diskWriteBytes)
        case .network:
            return MonitorFormatting.bytes(process.networkReceivedBytes + process.networkSentBytes)
        case .networkReceived:
            return MonitorFormatting.bytes(process.networkReceivedBytes)
        case .networkSent:
            return MonitorFormatting.bytes(process.networkSentBytes)
        case .state:
            return process.state
        case .threads:
            return "\(process.threadCount)"
        case .ports:
            return process.portsCount.map(String.init) ?? "—"
        case .preventingSleep:
            return process.preventsSleep.map { $0 ? "Yes" : "No" } ?? "—"
        case .wakeups:
            return process.wakeups.map(String.init) ?? "—"
        case .cpuTime:
            return process.cpuTime
        }
    }
}
