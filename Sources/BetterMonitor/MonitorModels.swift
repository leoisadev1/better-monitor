import Foundation
import CoreGraphics

enum MonitorPane: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case energy
    case disk
    case network
    case cache

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .energy: "Energy"
        case .disk: "Disk"
        case .network: "Network"
        case .cache: "Cache"
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .energy: "bolt"
        case .disk: "internaldrive"
        case .network: "network"
        case .cache: "shippingbox"
        }
    }

    var defaultSortKey: ProcessSortKey {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .energy: .energy
        case .disk: .disk
        case .network: .network
        case .cache: .network
        }
    }

    var keyboardEquivalent: Character {
        switch self {
        case .cpu: "1"
        case .memory: "2"
        case .energy: "3"
        case .disk: "4"
        case .network: "5"
        case .cache: "6"
        }
    }
}

enum ProcessScope: String, CaseIterable, Identifiable {
    case all
    case allHierarchically
    case mine
    case system
    case otherUsers
    case active
    case inactive
    case windowed
    case gpu
    case selected
    case lastTwelveHours

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Processes"
        case .allHierarchically: "All Processes, Hierarchically"
        case .mine: "My Processes"
        case .system: "System Processes"
        case .otherUsers: "Other User Processes"
        case .active: "Active Processes"
        case .inactive: "Inactive Processes"
        case .windowed: "Windowed Processes"
        case .gpu: "GPU Processes"
        case .selected: "Selected Processes"
        case .lastTwelveHours: "Applications in Last 12 Hours"
        }
    }
}

enum RefreshInterval: Double, CaseIterable, Identifiable {
    case veryFast = 1
    case fast = 2
    case normal = 5
    case slow = 10

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .veryFast: "Very Often (1 sec)"
        case .fast: "Often (2 sec)"
        case .normal: "Normal (5 sec)"
        case .slow: "Less Often (10 sec)"
        }
    }
}

enum DockIconMode: String, CaseIterable, Identifiable {
    case appIcon
    case cpuUsage
    case cpuHistory
    case networkUsage
    case diskActivity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appIcon: "Application Icon"
        case .cpuUsage: "Show CPU Usage"
        case .cpuHistory: "Show CPU History"
        case .networkUsage: "Show Network Usage"
        case .diskActivity: "Show Disk Activity"
        }
    }
}

enum ProcessSortKey: String, CaseIterable, Identifiable {
    case name
    case pid
    case user
    case cpu
    case memory
    case energy
    case disk
    case diskRead
    case diskWritten
    case network
    case networkReceived
    case networkSent
    case state
    case threads
    case ports
    case preventingSleep
    case wakeups
    case cpuTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Process Name"
        case .pid: "PID"
        case .user: "User"
        case .cpu: "% CPU"
        case .memory: "Memory"
        case .energy: "Energy Impact"
        case .disk: "Disk/s"
        case .diskRead: "Read/s"
        case .diskWritten: "Write/s"
        case .network: "Network"
        case .networkReceived: "Received Bytes"
        case .networkSent: "Sent Bytes"
        case .state: "State"
        case .threads: "Threads"
        case .ports: "Ports"
        case .preventingSleep: "Preventing Sleep"
        case .wakeups: "Wakeups/s"
        case .cpuTime: "CPU Time"
        }
    }
}

enum ProcessColumn: String, CaseIterable, Identifiable {
    case name
    case pid
    case user
    case cpu
    case memory
    case energy
    case disk
    case diskRead
    case diskWritten
    case network
    case networkReceived
    case networkSent
    case state
    case threads
    case ports
    case preventingSleep
    case wakeups
    case cpuTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Process Name"
        case .pid: "PID"
        case .user: "User"
        case .cpu: "% CPU"
        case .memory: "Memory"
        case .energy: "Energy Impact"
        case .disk: "Disk/s"
        case .diskRead: "Read/s"
        case .diskWritten: "Write/s"
        case .network: "Network"
        case .networkReceived: "Received Bytes"
        case .networkSent: "Sent Bytes"
        case .state: "State"
        case .threads: "Threads"
        case .ports: "Ports"
        case .preventingSleep: "Preventing Sleep"
        case .wakeups: "Wakeups/s"
        case .cpuTime: "CPU Time"
        }
    }

    var sortKey: ProcessSortKey? {
        switch self {
        case .name: .name
        case .pid: .pid
        case .user: .user
        case .cpu: .cpu
        case .memory: .memory
        case .energy: .energy
        case .disk: .disk
        case .diskRead: .diskRead
        case .diskWritten: .diskWritten
        case .network: .network
        case .networkReceived: .networkReceived
        case .networkSent: .networkSent
        case .state: .state
        case .threads: .threads
        case .ports: .ports
        case .preventingSleep: .preventingSleep
        case .wakeups: .wakeups
        case .cpuTime: .cpuTime
        }
    }

    var width: CGFloat {
        switch self {
        case .name: 240
        case .pid: 70
        case .user: 110
        case .cpu: 80
        case .memory: 100
        case .energy: 86
        case .disk: 100
        case .diskRead: 104
        case .diskWritten: 112
        case .network: 100
        case .networkReceived: 112
        case .networkSent: 100
        case .state: 60
        case .threads: 70
        case .ports: 70
        case .preventingSleep: 120
        case .wakeups: 82
        case .cpuTime: 90
        }
    }

    static func defaultVisible(for pane: MonitorPane) -> [ProcessColumn] {
        switch pane {
        case .cpu:
            [.name, .cpu, .cpuTime, .threads, .pid, .user]
        case .memory:
            [.name, .memory, .threads, .ports, .pid, .user]
        case .energy:
            [.name, .energy, .preventingSleep, .wakeups, .cpu, .network, .pid, .user]
        case .disk:
            [.name, .diskWritten, .diskRead, .disk, .pid, .user]
        case .network:
            [.name, .networkSent, .networkReceived, .network, .pid, .user]
        case .cache:
            [.name, .network, .disk, .pid, .user]
        }
    }

    static let defaultVisible: [ProcessColumn] = defaultVisible(for: .cpu)
}

enum ProcessAction: String, Identifiable {
    case inspect
    case openFileLocation
    case openFilesAndPorts
    case sample
    case quit
    case forceQuit
    case sendInterrupt
    case spindump
    case systemDiagnostics
    case spotlightDiagnostics

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .inspect: "Inspect"
        case .openFileLocation: "Open File Location"
        case .openFilesAndPorts: "Open Files and Ports"
        case .sample: "Sample Process"
        case .quit: "Quit"
        case .forceQuit: "Force Quit"
        case .sendInterrupt: "Send Interrupt"
        case .spindump: "Spindump"
        case .systemDiagnostics: "System Diagnostics"
        case .spotlightDiagnostics: "Spotlight Diagnostics"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .quit, .forceQuit, .sendInterrupt:
            true
        case .inspect, .openFileLocation, .openFilesAndPorts, .sample, .spindump, .systemDiagnostics, .spotlightDiagnostics:
            false
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .quit: "Quit"
        case .forceQuit: "Force Quit"
        case .sendInterrupt: "Interrupt"
        case .inspect, .openFileLocation, .openFilesAndPorts, .sample, .spindump, .systemDiagnostics, .spotlightDiagnostics:
            ""
        }
    }

    func confirmationTitle(for process: ProcessSnapshot) -> String {
        switch self {
        case .quit:
            "Quit \(process.name)?"
        case .forceQuit:
            "Force Quit \(process.name)?"
        case .sendInterrupt:
            "Send Interrupt to \(process.name)?"
        case .inspect, .openFileLocation, .openFilesAndPorts, .sample, .spindump, .systemDiagnostics, .spotlightDiagnostics:
            "Confirm Process Action"
        }
    }

    func confirmationMessage(for process: ProcessSnapshot) -> String {
        switch self {
        case .quit:
            "This asks process \(process.pid) to quit normally. Unsaved work in that process may be lost."
        case .forceQuit:
            "This immediately terminates process \(process.pid). Unsaved work in that process will be lost."
        case .sendInterrupt:
            "This sends SIGINT to process \(process.pid), which can stop command-line tools or interrupt work in progress."
        case .inspect, .openFileLocation, .openFilesAndPorts, .sample, .spindump, .systemDiagnostics, .spotlightDiagnostics:
            ""
        }
    }
}

struct ProcessInspection: Equatable {
    let pid: Int32
    let executablePath: String?
    let openFileDescriptorCount: Int?
    let inspectedAt: Date
}

struct ProcessOpenFiles: Equatable {
    let pid: Int32
    let lines: [String]
    let loadedAt: Date
}

struct PendingProcessAction: Identifiable, Equatable {
    let action: ProcessAction
    let process: ProcessSnapshot

    var id: String {
        "\(action.rawValue)-\(process.pid)"
    }
}

struct ProcessSnapshot: Identifiable, Equatable {
    var id: Int32 { pid }
    let pid: Int32
    let parentPID: Int32
    let user: String
    let command: String
    let name: String
    let cpuPercent: Double
    let memoryPercent: Double
    let residentMemoryBytes: Int64
    let virtualMemoryBytes: Int64
    let state: String
    let cpuTime: String
    let threadCount: Int
    let portsCount: Int?
    let preventsSleep: Bool?
    let wakeups: Int64?
    let energyImpact: Double
    let diskReadBytes: Int64
    let diskWriteBytes: Int64
    let networkReceivedBytes: Int64
    let networkSentBytes: Int64
    let hasVisibleWindows: Bool
    let usesGPU: Bool
    let launchDate: Date?
    var hierarchyLevel: Int = 0

    static let placeholder = ProcessSnapshot(
        pid: 0,
        parentPID: 0,
        user: "system",
        command: "Loading",
        name: "Loading Processes",
        cpuPercent: 0,
        memoryPercent: 0,
        residentMemoryBytes: 0,
        virtualMemoryBytes: 0,
        state: "",
        cpuTime: "",
        threadCount: 0,
        portsCount: nil,
        preventsSleep: nil,
        wakeups: nil,
        energyImpact: 0,
        diskReadBytes: 0,
        diskWriteBytes: 0,
        networkReceivedBytes: 0,
        networkSentBytes: 0,
        hasVisibleWindows: false,
        usesGPU: false,
        launchDate: nil,
        hierarchyLevel: 0
    )

    func withHierarchyLevel(_ level: Int) -> ProcessSnapshot {
        var copy = self
        copy.hierarchyLevel = level
        return copy
    }
}

struct MonitorSnapshot: Equatable {
    var capturedAt: Date
    var processes: [ProcessSnapshot]
    var summary: SystemSummary

    static let empty = MonitorSnapshot(
        capturedAt: .distantPast,
        processes: [],
        summary: .empty
    )
}

struct MonitorHistory: Equatable {
    var cpuSystem: [Double] = []
    var cpuUser: [Double] = []
    var memoryPressure: [Double] = []
    var energyImpact: [Double] = []
    var diskReadsPerSecond: [Double] = []
    var diskWritesPerSecond: [Double] = []
    var diskReadBytesPerSecond: [Double] = []
    var diskWrittenBytesPerSecond: [Double] = []
    var diskBytesPerSecond: [Double] = []
    var networkPacketsInPerSecond: [Double] = []
    var networkPacketsOutPerSecond: [Double] = []
    var networkBytesInPerSecond: [Double] = []
    var networkBytesOutPerSecond: [Double] = []
    var networkBytesPerSecond: [Double] = []
    var cachePressure: [Double] = []
    var sampleDurations: [Double] = []

    static let empty = MonitorHistory()

    mutating func append(snapshot: MonitorSnapshot, previous: MonitorSnapshot?, duration: TimeInterval, limit: Int = 90) {
        cpuSystem.append(snapshot.summary.cpu.systemPercent)
        cpuUser.append(snapshot.summary.cpu.userPercent)
        memoryPressure.append(snapshot.summary.memory.pressure * 100)
        energyImpact.append(snapshot.summary.energy.averageImpact)
        cachePressure.append(snapshot.summary.cache.pressure * 100)
        sampleDurations.append(duration * 1_000)

        let interval = previous.map { max(0.001, snapshot.capturedAt.timeIntervalSince($0.capturedAt)) } ?? 1
        if let previous {
            let diskReadsDelta = max(0, snapshot.summary.disk.reads - previous.summary.disk.reads)
            let diskWritesDelta = max(0, snapshot.summary.disk.writes - previous.summary.disk.writes)
            let diskReadBytesDelta = max(0, snapshot.summary.disk.readBytes - previous.summary.disk.readBytes)
            let diskWrittenBytesDelta = max(0, snapshot.summary.disk.writtenBytes - previous.summary.disk.writtenBytes)
            let networkPacketsInDelta = max(0, snapshot.summary.network.packetsIn - previous.summary.network.packetsIn)
            let networkPacketsOutDelta = max(0, snapshot.summary.network.packetsOut - previous.summary.network.packetsOut)
            let networkBytesInDelta = max(0, snapshot.summary.network.bytesIn - previous.summary.network.bytesIn)
            let networkBytesOutDelta = max(0, snapshot.summary.network.bytesOut - previous.summary.network.bytesOut)

            diskReadsPerSecond.append(Double(diskReadsDelta) / interval)
            diskWritesPerSecond.append(Double(diskWritesDelta) / interval)
            diskReadBytesPerSecond.append(Double(diskReadBytesDelta) / interval)
            diskWrittenBytesPerSecond.append(Double(diskWrittenBytesDelta) / interval)
            diskBytesPerSecond.append(Double(diskReadBytesDelta + diskWrittenBytesDelta) / interval)
            networkPacketsInPerSecond.append(Double(networkPacketsInDelta) / interval)
            networkPacketsOutPerSecond.append(Double(networkPacketsOutDelta) / interval)
            networkBytesInPerSecond.append(Double(networkBytesInDelta) / interval)
            networkBytesOutPerSecond.append(Double(networkBytesOutDelta) / interval)
            networkBytesPerSecond.append(Double(networkBytesInDelta + networkBytesOutDelta) / interval)
        } else {
            diskReadsPerSecond.append(0)
            diskWritesPerSecond.append(0)
            diskReadBytesPerSecond.append(0)
            diskWrittenBytesPerSecond.append(0)
            diskBytesPerSecond.append(0)
            networkPacketsInPerSecond.append(0)
            networkPacketsOutPerSecond.append(0)
            networkBytesInPerSecond.append(0)
            networkBytesOutPerSecond.append(0)
            networkBytesPerSecond.append(0)
        }

        trim(limit: limit)
    }

    func values(for pane: MonitorPane) -> [Double] {
        switch pane {
        case .cpu:
            return zip(cpuSystem, cpuUser).map(+)
        case .memory:
            return memoryPressure
        case .energy:
            return energyImpact
        case .disk:
            return diskBytesPerSecond
        case .network:
            return networkBytesPerSecond
        case .cache:
            return cachePressure
        }
    }

    private mutating func trim(limit: Int) {
        cpuSystem.trimToSuffix(limit)
        cpuUser.trimToSuffix(limit)
        memoryPressure.trimToSuffix(limit)
        energyImpact.trimToSuffix(limit)
        diskReadsPerSecond.trimToSuffix(limit)
        diskWritesPerSecond.trimToSuffix(limit)
        diskReadBytesPerSecond.trimToSuffix(limit)
        diskWrittenBytesPerSecond.trimToSuffix(limit)
        diskBytesPerSecond.trimToSuffix(limit)
        networkPacketsInPerSecond.trimToSuffix(limit)
        networkPacketsOutPerSecond.trimToSuffix(limit)
        networkBytesInPerSecond.trimToSuffix(limit)
        networkBytesOutPerSecond.trimToSuffix(limit)
        networkBytesPerSecond.trimToSuffix(limit)
        cachePressure.trimToSuffix(limit)
        sampleDurations.trimToSuffix(limit)
    }
}

private extension Array {
    mutating func trimToSuffix(_ limit: Int) {
        if count > limit {
            self = Array(suffix(limit))
        }
    }
}

struct SystemSummary: Equatable {
    var cpu: CPUSummary
    var memory: MemorySummary
    var energy: EnergySummary
    var disk: DiskSummary
    var network: NetworkSummary
    var cache: CacheSummary

    static let empty = SystemSummary(
        cpu: .empty,
        memory: .empty,
        energy: .empty,
        disk: .empty,
        network: .empty,
        cache: .empty
    )
}

struct CPUSummary: Equatable {
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double
    var processCount: Int
    var threadCount: Int
    var loadAverage: [Double]

    static let empty = CPUSummary(userPercent: 0, systemPercent: 0, idlePercent: 100, processCount: 0, threadCount: 0, loadAverage: [])
}

struct MemorySummary: Equatable {
    var physicalMemoryBytes: Int64
    var usedBytes: Int64
    var appBytes: Int64
    var wiredBytes: Int64
    var compressedBytes: Int64
    var cachedBytes: Int64
    var swapUsedBytes: Int64
    var pressure: Double

    static let empty = MemorySummary(
        physicalMemoryBytes: 0,
        usedBytes: 0,
        appBytes: 0,
        wiredBytes: 0,
        compressedBytes: 0,
        cachedBytes: 0,
        swapUsedBytes: 0,
        pressure: 0
    )
}

struct EnergySummary: Equatable {
    var totalImpact: Double
    var averageImpact: Double
    var batteryPercent: Double?
    var powerSource: String
    var preventingSleepCount: Int

    static let empty = EnergySummary(totalImpact: 0, averageImpact: 0, batteryPercent: nil, powerSource: "Unknown", preventingSleepCount: 0)
}

struct DiskSummary: Equatable {
    var reads: Int64
    var writes: Int64
    var readBytes: Int64
    var writtenBytes: Int64

    static let empty = DiskSummary(reads: 0, writes: 0, readBytes: 0, writtenBytes: 0)
}

struct NetworkSummary: Equatable {
    var packetsIn: Int64
    var packetsOut: Int64
    var bytesIn: Int64
    var bytesOut: Int64

    static let empty = NetworkSummary(packetsIn: 0, packetsOut: 0, bytesIn: 0, bytesOut: 0)
}

struct CacheSummary: Equatable {
    var isAvailable: Bool
    var isActive: Bool
    var servedBytes: Int64
    var droppedBytes: Int64
    var originBytes: Int64
    var peerBytes: Int64
    var pressure: Double

    static let empty = CacheSummary(isAvailable: false, isActive: false, servedBytes: 0, droppedBytes: 0, originBytes: 0, peerBytes: 0, pressure: 0)
}

struct ProcessFilter: Equatable {
    var query: String = ""
    var scope: ProcessScope = .all
    var selectedPID: Int32?
    var currentUser: String = NSUserName()

    func matches(_ process: ProcessSnapshot) -> Bool {
        let queryMatches = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || process.name.localizedCaseInsensitiveContains(query)
            || process.command.localizedCaseInsensitiveContains(query)
            || String(process.pid).contains(query)
            || process.user.localizedCaseInsensitiveContains(query)

        guard queryMatches else { return false }

        switch scope {
        case .all, .allHierarchically:
            return true
        case .mine:
            return process.user == currentUser
        case .system:
            return process.user == "root" || process.pid < 500
        case .otherUsers:
            return process.user != currentUser && process.user != "root"
        case .active:
            return process.cpuPercent > 0.1 || process.state.contains("R")
        case .inactive:
            return process.cpuPercent <= 0.1 && !process.state.contains("R")
        case .windowed:
            return process.hasVisibleWindows
        case .gpu:
            return process.usesGPU
        case .selected:
            return process.pid == selectedPID
        case .lastTwelveHours:
            guard let launchDate = process.launchDate else { return false }
            return process.hasVisibleWindows && launchDate >= Date().addingTimeInterval(-12 * 60 * 60)
        }
    }
}
