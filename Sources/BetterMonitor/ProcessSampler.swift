import Foundation
import Darwin
import CoreGraphics
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import BetterMonitorC

protocol MonitorSampling: Sendable {
    func capture(focusedPane: MonitorPane, focusedScope: ProcessScope) async -> MonitorSnapshot
}

extension MonitorSampling {
    func capture() async -> MonitorSnapshot {
        await capture(focusedPane: .cpu, focusedScope: .all)
    }

    func capture(focusedPane: MonitorPane) async -> MonitorSnapshot {
        await capture(focusedPane: focusedPane, focusedScope: .all)
    }
}

actor SystemMonitorSampler: MonitorSampling {
    private var previousCPUTicks: HostCPUTicks?
    private var previousProcessCPUTimes: [Int32: UInt64] = [:]
    private var previousProcessCaptureDate: Date?

    func capture(focusedPane: MonitorPane, focusedScope: ProcessScope) async -> MonitorSnapshot {
        let processCPUTimes = previousProcessCPUTimes
        let processCaptureDate = previousProcessCaptureDate
        let raw = await Task.detached(priority: .utility) {
            let capturedAt = Date()
            let networkByPID = focusedPane == .network ? PerProcessNetworkParser.capture() : [:]
            let sleepPreventingPIDs = focusedPane == .energy ? (PowerAssertionReader.preventingSleepPIDs() ?? SleepAssertionParser.capture()) : []
            let visibleWindowPIDs = focusedScope.needsWindowOwnership ? WindowOwnershipReader.visibleWindowPIDs() : []
            let processCapture = Self.captureProcesses(
                networkByPID: networkByPID,
                sleepPreventingPIDs: sleepPreventingPIDs,
                visibleWindowPIDs: visibleWindowPIDs,
                includeResourceUsage: focusedPane.needsResourceUsageCounters,
                previousCPUTimes: processCPUTimes,
                previousCaptureDate: processCaptureDate,
                capturedAt: capturedAt
            )
            return RawCapture(
                capturedAt: capturedAt,
                processes: processCapture.processes,
                processCPUTimes: processCapture.cpuTimes,
                cpuTicks: HostCPUReader.readTicks(),
                memory: Self.captureMemory(processes: processCapture.processes, detailed: true),
                energy: Self.captureEnergy(processes: processCapture.processes, sleepPreventingPIDs: sleepPreventingPIDs),
                disk: Self.captureDisk(processes: processCapture.processes, detailed: true),
                network: Self.captureNetwork(),
                cache: focusedPane == .cache ? Self.captureCache() : .empty
            )
        }.value

        let cpu = Self.captureCPU(processes: raw.processes, currentTicks: raw.cpuTicks, previousTicks: previousCPUTicks)
        previousCPUTicks = raw.cpuTicks
        previousProcessCPUTimes = raw.processCPUTimes
        previousProcessCaptureDate = raw.capturedAt

        return MonitorSnapshot(
            capturedAt: raw.capturedAt,
            processes: raw.processes,
            summary: SystemSummary(
                cpu: cpu,
                memory: raw.memory,
                energy: raw.energy,
                disk: raw.disk,
                network: raw.network,
                cache: raw.cache
            )
        )
    }

    private struct RawCapture: Sendable {
        let capturedAt: Date
        let processes: [ProcessSnapshot]
        let processCPUTimes: [Int32: UInt64]
        let cpuTicks: HostCPUTicks?
        let memory: MemorySummary
        let energy: EnergySummary
        let disk: DiskSummary
        let network: NetworkSummary
        let cache: CacheSummary
    }

    private struct ProcessCapture: Sendable {
        let processes: [ProcessSnapshot]
        let cpuTimes: [Int32: UInt64]
    }

    private static func captureProcesses(
        networkByPID: [Int32: PerProcessNetworkSample],
        sleepPreventingPIDs: Set<Int32>,
        visibleWindowPIDs: Set<Int32>,
        includeResourceUsage: Bool,
        previousCPUTimes: [Int32: UInt64],
        previousCaptureDate: Date?,
        capturedAt: Date
    ) -> ProcessCapture {
        let infos = ProcessInfoSampler.allBSDInfos()
        var userCache: [uid_t: String] = [:]
        var cpuTimes: [Int32: UInt64] = [:]
        let physicalMemory = max(1, Double(ProcessInfo.processInfo.physicalMemory))
        let elapsedNanoseconds = previousCaptureDate.map { max(0.001, capturedAt.timeIntervalSince($0)) * 1_000_000_000 }
        let processes = infos.compactMap { bsd -> ProcessSnapshot? in
            let pid = bsd.pid
            guard let task = ProcessInfoSampler.taskInfo(pid: pid)
            else {
                return nil
            }

            let cpuTime = task.totalCPUTimeNanoseconds
            cpuTimes[pid] = cpuTime
            let cpuPercent: Double
            if let previous = previousCPUTimes[pid], let elapsedNanoseconds {
                cpuPercent = Double(cpuTime.saturatingSubtract(previous)) / elapsedNanoseconds * 100
            } else {
                cpuPercent = 0
            }

            let command = bsd.name
            let displayName = bsd.name
            let rusage = includeResourceUsage ? ProcessInfoSampler.rusage(pid: pid) : nil
            let memoryBytes = rusage?.physicalFootprintBytes ?? task.residentMemoryBytes
            let memoryPercent = Double(memoryBytes) / physicalMemory * 100
            let network = networkByPID[pid]
            let energyFromCounters = rusage.map { Self.energyImpact(from: $0.energyNanojoules) } ?? 0
            let energy = max(energyFromCounters, cpuPercent * 0.65 + memoryPercent * 0.35)
            let hasVisibleWindows = visibleWindowPIDs.contains(pid) || Self.appearsWindowed(path: command, name: displayName, status: bsd.status)

            return ProcessSnapshot(
                pid: pid,
                parentPID: bsd.parentPID,
                user: userName(for: bsd.uid, cache: &userCache),
                command: command,
                name: displayName.isEmpty ? String(pid) : displayName,
                cpuPercent: cpuPercent,
                memoryPercent: memoryPercent,
                residentMemoryBytes: memoryBytes,
                virtualMemoryBytes: task.virtualMemoryBytes,
                state: Self.stateLabel(for: bsd.status),
                cpuTime: Self.cpuTimeString(nanoseconds: cpuTime),
                threadCount: task.threadCount,
                portsCount: nil,
                preventsSleep: sleepPreventingPIDs.isEmpty ? nil : sleepPreventingPIDs.contains(pid),
                wakeups: rusage?.wakeups,
                energyImpact: energy,
                diskReadBytes: rusage?.readBytes ?? 0,
                diskWriteBytes: rusage?.writtenBytes ?? 0,
                networkReceivedBytes: network?.bytesIn ?? 0,
                networkSentBytes: network?.bytesOut ?? 0,
                hasVisibleWindows: hasVisibleWindows,
                usesGPU: hasVisibleWindows || Self.appearsGPUBacked(path: command, name: displayName),
                launchDate: bsd.launchDate
            )
        }
        .sorted { lhs, rhs in
            lhs.cpuPercent == rhs.cpuPercent ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : lhs.cpuPercent > rhs.cpuPercent
        }

        return ProcessCapture(processes: processes, cpuTimes: cpuTimes)
    }

    private static func captureCPU(processes: [ProcessSnapshot], currentTicks: HostCPUTicks?, previousTicks: HostCPUTicks?) -> CPUSummary {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        let percentages: (user: Double, system: Double, idle: Double)
        if let currentTicks, let previousTicks {
            percentages = HostCPUReader.percentages(current: currentTicks, previous: previousTicks)
        } else {
            let busy = processes.reduce(0) { $0 + $1.cpuPercent }
            let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let normalizedBusy = min(100, busy / Double(processorCount))
            let system = min(normalizedBusy * 0.35, 100)
            let user = min(max(normalizedBusy - system, 0), 100)
            percentages = (user: user, system: system, idle: max(0, 100 - user - system))
        }
        let threadCount = processes.reduce(0) { $0 + $1.threadCount }
        return CPUSummary(
            userPercent: percentages.user,
            systemPercent: percentages.system,
            idlePercent: percentages.idle,
            processCount: processes.count,
            threadCount: threadCount,
            loadAverage: loads
        )
    }

    private static func captureMemory(processes: [ProcessSnapshot], detailed: Bool) -> MemorySummary {
        let physical = Int64(ProcessInfo.processInfo.physicalMemory)
        let resident = processes.reduce(Int64(0)) { $0 + $1.residentMemoryBytes }
        guard detailed else {
            return MemorySummary(
                physicalMemoryBytes: physical,
                usedBytes: min(physical, resident),
                appBytes: resident,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                swapUsedBytes: 0,
                pressure: physical > 0 ? (Double(resident) / Double(physical)).clampedPercent : 0
            )
        }
        let vm = MachMemoryReader.read()
        let wired = vm?.wiredBytes ?? 0
        let compressed = vm?.compressedBytes ?? 0
        let cached = vm?.cachedBytes ?? 0
        let used = min(physical, max(resident, vm?.usedBytes ?? resident + wired + compressed))
        let pressure = physical > 0 ? Double(used) / Double(physical) : 0
        return MemorySummary(
            physicalMemoryBytes: physical,
            usedBytes: used,
            appBytes: resident,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            swapUsedBytes: vm?.swapUsedBytes ?? 0,
            pressure: pressure.clampedPercent
        )
    }

    private static func captureEnergy(processes: [ProcessSnapshot], sleepPreventingPIDs: Set<Int32>) -> EnergySummary {
        let totalImpact = processes.reduce(0) { $0 + $1.energyImpact }
        let averageImpact = processes.isEmpty ? 0 : totalImpact / Double(processes.count)
        let power = PowerSourceReader.read()
        let fallbackPower = power == nil ? ((try? Shell.run("/usr/bin/pmset", ["-g", "batt"]).output) ?? "") : ""
        let battery = power?.batteryPercent ?? BatteryParser.parsePercent(fallbackPower)
        let source = power?.source ?? (fallbackPower.contains("AC Power") ? "Power Adapter" : fallbackPower.contains("Battery Power") ? "Battery" : "Unknown")
        return EnergySummary(totalImpact: totalImpact, averageImpact: averageImpact, batteryPercent: battery, powerSource: source, preventingSleepCount: sleepPreventingPIDs.count)
    }

    private static func captureDisk(processes: [ProcessSnapshot], detailed: Bool) -> DiskSummary {
        let readBytes = processes.reduce(Int64(0)) { $0 + $1.diskReadBytes }
        let writeBytes = processes.reduce(Int64(0)) { $0 + $1.diskWriteBytes }
        guard detailed else {
            return DiskSummary(reads: 0, writes: 0, readBytes: max(readBytes, 0), writtenBytes: max(writeBytes, 0))
        }
        if let disk = DiskActivityReader.read() {
            return DiskSummary(
                reads: disk.reads,
                writes: disk.writes,
                readBytes: max(disk.readBytes, readBytes),
                writtenBytes: max(disk.writtenBytes, writeBytes)
            )
        }
        let output = (try? Shell.run("/usr/sbin/iostat", ["-Id", "-c", "1"]).output) ?? ""
        let numbers = output
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int64($0) }
        return DiskSummary(
            reads: numbers.first ?? 0,
            writes: numbers.dropFirst().first ?? 0,
            readBytes: max(readBytes, 0),
            writtenBytes: max(writeBytes, 0)
        )
    }

    private static func captureNetwork() -> NetworkSummary {
        NetworkInterfaceReader.read() ?? NetworkParser.parse((try? Shell.run("/usr/sbin/netstat", ["-ibn"]).output) ?? "")
    }

    private static func captureCache() -> CacheSummary {
        let status = (try? Shell.run("/usr/bin/AssetCacheManagerUtil", ["status"], timeout: 1).output) ?? ""
        guard !status.isEmpty else { return .empty }
        return CacheSummary(
            isAvailable: true,
            isActive: status.localizedCaseInsensitiveContains("Activated: true") || status.localizedCaseInsensitiveContains("Active: true"),
            servedBytes: CacheParser.byteValue(status, keys: ["Bytes Served", "Data Served"]),
            droppedBytes: CacheParser.byteValue(status, keys: ["Bytes Dropped", "Data Dropped"]),
            originBytes: CacheParser.byteValue(status, keys: ["Bytes From Origin"]),
            peerBytes: CacheParser.byteValue(status, keys: ["Bytes From Peers"]),
            pressure: status.localizedCaseInsensitiveContains("pressure") ? 0.5 : 0
        )
    }

    private static func userName(for uid: uid_t, cache: inout [uid_t: String]) -> String {
        if let cached = cache[uid] {
            return cached
        }
        let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        cache[uid] = name
        return name
    }

    private static func stateLabel(for status: UInt32) -> String {
        switch Int32(status) {
        case SRUN: "R"
        case SSLEEP: "S"
        case SSTOP: "T"
        case SZOMB: "Z"
        case SIDL: "I"
        default: "?"
        }
    }

    private static func cpuTimeString(nanoseconds: UInt64) -> String {
        let centiseconds = nanoseconds / 10_000_000
        let totalSeconds = centiseconds / 100
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        let hundredths = centiseconds % 100
        if hours > 0 {
            return String(format: "%llu:%02llu:%02llu.%02llu", hours, minutes, seconds, hundredths)
        }
        return String(format: "%llu:%02llu.%02llu", minutes, seconds, hundredths)
    }

    private static func appearsWindowed(path: String, name: String, status: UInt32) -> Bool {
        guard Int32(status) != SZOMB else { return false }
        return path.hasPrefix("/Applications/") ||
            path.contains(".app/Contents/MacOS/") ||
            name.localizedCaseInsensitiveContains("WindowServer")
    }

    private static func appearsGPUBacked(path: String, name: String) -> Bool {
        let searchable = "\(path) \(name)"
        return searchable.localizedCaseInsensitiveContains("WindowServer") ||
            searchable.localizedCaseInsensitiveContains("Metal") ||
            searchable.localizedCaseInsensitiveContains("GPU") ||
            searchable.localizedCaseInsensitiveContains("CoreAnimation")
    }

    private static func energyImpact(from nanojoules: UInt64) -> Double {
        guard nanojoules > 0 else { return 0 }
        return min(999, log10(Double(nanojoules)))
    }
}

struct PerProcessNetworkSample: Equatable, Sendable {
    let bytesIn: Int64
    let bytesOut: Int64
}

enum PerProcessNetworkParser {
    static func capture() -> [Int32: PerProcessNetworkSample] {
        let output = (try? Shell.run("/usr/bin/nettop", ["-P", "-L", "1", "-x", "-n", "-J", "bytes_in,bytes_out"], timeout: 2).output) ?? ""
        return parse(output)
    }

    static func parse(_ output: String) -> [Int32: PerProcessNetworkSample] {
        var samples: [Int32: PerProcessNetworkSample] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3,
                  let pid = parsePID(String(columns[0])),
                  let bytesIn = Int64(columns[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let bytesOut = Int64(columns[2].trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                continue
            }
            let existing = samples[pid] ?? PerProcessNetworkSample(bytesIn: 0, bytesOut: 0)
            samples[pid] = PerProcessNetworkSample(
                bytesIn: existing.bytesIn + bytesIn,
                bytesOut: existing.bytesOut + bytesOut
            )
        }
        return samples
    }

    private static func parsePID(_ processKey: String) -> Int32? {
        guard let dotIndex = processKey.lastIndex(of: ".") else { return nil }
        let suffix = processKey[processKey.index(after: dotIndex)...]
        return Int32(suffix)
    }
}

enum SleepAssertionParser {
    static func capture() -> Set<Int32> {
        let output = (try? Shell.run("/usr/bin/pmset", ["-g", "assertions"]).output) ?? ""
        return parse(output)
    }

    static func parse(_ output: String) -> Set<Int32> {
        var pids = Set<Int32>()
        for line in output.split(separator: "\n") {
            guard line.localizedCaseInsensitiveContains("prevent"),
                  let pid = parsePID(String(line))
            else {
                continue
            }
            pids.insert(pid)
        }
        return pids
    }

    private static func parsePID(_ line: String) -> Int32? {
        guard let range = line.range(of: "pid ") else { return nil }
        let suffix = line[range.upperBound...]
        let digits = suffix.drop { $0 == " " }.prefix { $0.isNumber }
        return Int32(String(digits))
    }
}

struct PowerSourceSnapshot: Equatable {
    let batteryPercent: Double?
    let source: String
}

enum PowerSourceReader {
    static func read() -> PowerSourceSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty
        else {
            return nil
        }

        var batteryPercent: Double?
        var source = "Unknown"

        for powerSource in sources {
            guard let description = IOPSGetPowerSourceDescription(info, powerSource)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let current = numericValue(description[kIOPSCurrentCapacityKey as String]),
               let maximum = numericValue(description[kIOPSMaxCapacityKey as String]),
               maximum > 0 {
                batteryPercent = current / maximum * 100
            }
            if let state = description[kIOPSPowerSourceStateKey as String] as? String {
                source = state.localizedCaseInsensitiveContains("AC") ? "Power Adapter" : state.localizedCaseInsensitiveContains("Battery") ? "Battery" : state
            }
            if batteryPercent != nil || source != "Unknown" {
                break
            }
        }

        return PowerSourceSnapshot(batteryPercent: batteryPercent, source: source)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let value as Double:
            value
        case let value as Int:
            Double(value)
        default:
            nil
        }
    }
}

enum PowerAssertionReader {
    static func preventingSleepPIDs() -> Set<Int32>? {
        var rawAssertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&rawAssertions) == kIOReturnSuccess,
              let assertionsByProcess = rawAssertions?.takeRetainedValue() as? [AnyHashable: Any]
        else {
            return nil
        }

        var pids = Set<Int32>()
        for (rawPID, rawAssertions) in assertionsByProcess {
            guard let assertions = rawAssertions as? [[String: Any]] else { continue }
            for assertion in assertions where preventsSleep(assertion) {
                if let pid = numericPID(assertion["AssertPID"]) ?? numericPID(rawPID.base) {
                    pids.insert(pid)
                }
            }
        }
        return pids
    }

    private static func preventsSleep(_ assertion: [String: Any]) -> Bool {
        let level = (assertion["AssertLevel"] as? NSNumber)?.intValue ?? 0
        guard level != 0 else { return false }
        let type = "\(assertion["AssertType"] ?? "") \(assertion["AssertionTrueType"] ?? "")"
        return type.localizedCaseInsensitiveContains("Prevent")
    }

    private static func numericPID(_ value: Any?) -> Int32? {
        switch value {
        case let number as NSNumber:
            Int32(truncating: number)
        case let value as Int:
            Int32(value)
        case let value as Int32:
            value
        case let value as String:
            Int32(value)
        default:
            nil
        }
    }
}

enum WindowOwnershipReader {
    static func visibleWindowPIDs() -> Set<Int32> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var pids = Set<Int32>()
        for window in rawWindows {
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? NSNumber
            else {
                continue
            }
            pids.insert(Int32(truncating: ownerPID))
        }
        return pids
    }
}

private extension MonitorPane {
    var needsResourceUsageCounters: Bool {
        switch self {
        case .memory, .energy, .disk:
            true
        case .cpu, .network, .cache:
            false
        }
    }
}

private extension ProcessScope {
    var needsWindowOwnership: Bool {
        switch self {
        case .windowed, .gpu, .lastTwelveHours:
            true
        case .all, .allHierarchically, .mine, .system, .otherUsers, .active, .inactive, .selected:
            false
        }
    }
}

enum ProcessInfoSampler {
    struct TaskInfo: Equatable {
        let residentMemoryBytes: Int64
        let virtualMemoryBytes: Int64
        let threadCount: Int
        let totalCPUTimeNanoseconds: UInt64
    }

    struct BSDInfo: Equatable {
        let pid: Int32
        let parentPID: Int32
        let uid: uid_t
        let status: UInt32
        let name: String
        let launchDate: Date?
    }

    struct Rusage: Equatable {
        let readBytes: Int64
        let writtenBytes: Int64
        let physicalFootprintBytes: Int64
        let residentSizeBytes: Int64
        let energyNanojoules: UInt64
        let wakeups: Int64
    }

    static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        let result = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        }
        guard result > 0 else { return [] }
        let populatedCount = min(pids.count, Int(result))
        var populatedPIDs: [Int32] = []
        populatedPIDs.reserveCapacity(populatedCount)
        for index in 0..<populatedCount where pids[index] > 0 {
            populatedPIDs.append(Int32(pids[index]))
        }
        return populatedPIDs
    }

    static func allBSDInfos() -> [BSDInfo] {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var byteCount = 0
        guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0,
              byteCount > 0
        else {
            return allPIDs().compactMap { bsdInfo(pid: $0) }
        }

        let processCount = byteCount / MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: processCount)
        let result = processes.withUnsafeMutableBufferPointer { buffer in
            sysctl(&mib, u_int(mib.count), buffer.baseAddress, &byteCount, nil, 0)
        }
        guard result == 0 else {
            return allPIDs().compactMap { bsdInfo(pid: $0) }
        }

        let populatedCount = min(processes.count, byteCount / MemoryLayout<kinfo_proc>.stride)
        var infos: [BSDInfo] = []
        infos.reserveCapacity(populatedCount)
        for index in 0..<populatedCount {
            let process = processes[index]
            let pid = Int32(process.kp_proc.p_pid)
            guard pid > 0 else { continue }
            let name = tupleString(process.kp_proc.p_comm)
            let launchSeconds = process.kp_proc.p_starttime.tv_sec
            infos.append(BSDInfo(
                pid: pid,
                parentPID: Int32(process.kp_eproc.e_ppid),
                uid: process.kp_eproc.e_ucred.cr_uid,
                status: UInt32(process.kp_proc.p_stat),
                name: name,
                launchDate: launchSeconds > 0 ? Date(timeIntervalSince1970: TimeInterval(launchSeconds)) : nil
            ))
        }
        return infos
    }

    static func bsdInfo(pid: Int32) -> BSDInfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size))
            }
        }
        guard result == Int32(size) else { return nil }
        let name = tupleString(info.pbi_name).isEmpty ? tupleString(info.pbi_comm) : tupleString(info.pbi_name)
        let launchDate = info.pbi_start_tvsec > 0 ? Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)) : nil
        return BSDInfo(
            pid: pid,
            parentPID: Int32(info.pbi_ppid),
            uid: info.pbi_uid,
            status: info.pbi_status,
            name: name,
            launchDate: launchDate
        )
    }

    static func taskInfo(pid: Int32) -> TaskInfo? {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }
        guard result == Int32(size) else { return nil }
        return TaskInfo(
            residentMemoryBytes: Int64(clamping: info.pti_resident_size),
            virtualMemoryBytes: Int64(clamping: info.pti_virtual_size),
            threadCount: max(0, Int(info.pti_threadnum)),
            totalCPUTimeNanoseconds: info.pti_total_user + info.pti_total_system
        )
    }

    static func path(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 16_384)
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else {
            return pid == getpid() ? currentExecutablePath() : nil
        }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: pathBytes, as: UTF8.self)
    }

    static func rusage(pid: Int32) -> Rusage? {
        var usage = BetterMonitorRusage()
        guard better_monitor_pid_rusage(pid, &usage) == 0 else { return nil }
        return Rusage(
            readBytes: Int64(clamping: usage.disk_read_bytes),
            writtenBytes: Int64(clamping: usage.disk_written_bytes),
            physicalFootprintBytes: Int64(clamping: usage.physical_footprint_bytes),
            residentSizeBytes: Int64(clamping: usage.resident_size_bytes),
            energyNanojoules: usage.energy_nanojoules,
            wakeups: Int64(clamping: usage.wakeups)
        )
    }

    static func openFileDescriptorCount(pid: Int32) -> Int? {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return nil }
        return Int(bytes) / MemoryLayout<proc_fdinfo>.size
    }

    private static func tupleString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: CChar.self)
            let characters = bytes.prefix { $0 != 0 }
            return String(decoding: characters.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    private static func currentExecutablePath() -> String? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        let result = buffer.withUnsafeMutableBufferPointer {
            _NSGetExecutablePath($0.baseAddress, &size)
        }
        guard result == 0 else { return nil }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: pathBytes, as: UTF8.self)
    }
}

struct HostCPUTicks: Equatable, Sendable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var total: UInt64 {
        user + system + idle + nice
    }
}

enum HostCPUReader {
    static func readTicks() -> HostCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return HostCPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    static func percentages(current: HostCPUTicks, previous: HostCPUTicks) -> (user: Double, system: Double, idle: Double) {
        let user = current.user.saturatingSubtract(previous.user)
        let system = current.system.saturatingSubtract(previous.system)
        let idle = current.idle.saturatingSubtract(previous.idle)
        let nice = current.nice.saturatingSubtract(previous.nice)
        let total = max(1, user + system + idle + nice)

        return (
            user: Double(user + nice) / Double(total) * 100,
            system: Double(system) / Double(total) * 100,
            idle: Double(idle) / Double(total) * 100
        )
    }
}

struct MachMemoryStats: Equatable {
    let usedBytes: Int64
    let wiredBytes: Int64
    let compressedBytes: Int64
    let cachedBytes: Int64
    let swapUsedBytes: Int64
}

enum MachMemoryReader {
    static func read() -> MachMemoryStats? {
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageBytes = UInt64(pageSize)
        let active = UInt64(stats.active_count) * pageBytes
        let inactive = UInt64(stats.inactive_count) * pageBytes
        let wired = UInt64(stats.wire_count) * pageBytes
        let compressed = UInt64(stats.compressor_page_count) * pageBytes
        let cached = UInt64(stats.purgeable_count + stats.speculative_count) * pageBytes
        return MachMemoryStats(
            usedBytes: Int64(clamping: active + inactive + wired + compressed),
            wiredBytes: Int64(clamping: wired),
            compressedBytes: Int64(clamping: compressed),
            cachedBytes: Int64(clamping: cached),
            swapUsedBytes: readSwapUsedBytes()
        )
    }

    private static func readSwapUsedBytes() -> Int64 {
        var usage = xsw_usage()
        var byteCount = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &usage, &byteCount, nil, 0)
        guard result == 0 else { return 0 }
        return Int64(clamping: usage.xsu_used)
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}

enum ProcessListParser {
    static func parsePSOutput(_ output: String) -> [ProcessSnapshot] {
        output
            .split(separator: "\n")
            .compactMap(parseLine)
            .sorted { $0.cpuPercent == $1.cpuPercent ? $0.name < $1.name : $0.cpuPercent > $1.cpuPercent }
    }

    static func parseLine(_ line: Substring) -> ProcessSnapshot? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 10,
              let pid = Int32(parts[0]),
              let parentPID = Int32(parts[1]),
              let cpu = Double(parts[4]),
              let memory = Double(parts[5]),
              let rss = Int64(parts[6]),
              let virtual = Int64(parts[7])
        else {
            return nil
        }

        let command = String(parts[3])
        let name = URL(fileURLWithPath: command).lastPathComponent
        let state = String(parts[8])
        let cpuTime = String(parts[9])
        let estimatedThreads = max(1, Int(cpu.rounded(.up)))
        let energy = max(0, cpu * 0.65 + memory * 0.35)

        return ProcessSnapshot(
            pid: pid,
            parentPID: parentPID,
            user: String(parts[2]),
            command: command,
            name: name.isEmpty ? command : name,
            cpuPercent: cpu,
            memoryPercent: memory,
            residentMemoryBytes: rss * 1024,
            virtualMemoryBytes: virtual * 1024,
            state: state,
            cpuTime: cpuTime,
            threadCount: estimatedThreads,
            portsCount: nil,
            preventsSleep: nil,
            wakeups: nil,
            energyImpact: energy,
            diskReadBytes: 0,
            diskWriteBytes: 0,
            networkReceivedBytes: 0,
            networkSentBytes: 0,
            hasVisibleWindows: state.contains("S") == false && pid > 500,
            usesGPU: command.localizedCaseInsensitiveContains("WindowServer") || command.localizedCaseInsensitiveContains("Metal"),
            launchDate: nil
        )
    }
}

enum VMStatParser {
    static func parse(_ output: String) -> [String: Int64] {
        let pageSize = parsePageSize(output) ?? 16_384
        var values: [String: Int64] = [:]
        for line in output.split(separator: "\n") {
            let split = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard split.count == 2 else { continue }
            let key = split[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = split[1].filter { $0.isNumber }
            if let pages = Int64(rawValue) {
                values[key] = pages * pageSize
            }
        }
        return values
    }

    private static func parsePageSize(_ output: String) -> Int64? {
        guard let firstLine = output.split(separator: "\n").first,
              let start = firstLine.range(of: "page size of ")
        else {
            return nil
        }
        let suffix = firstLine[start.upperBound...]
        let digits = suffix.filter { $0.isNumber }
        return Int64(digits)
    }
}

enum SwapParser {
    static func parse(_ output: String) -> Int64 {
        guard let usedRange = output.range(of: "used = ") else { return 0 }
        let tail = output[usedRange.upperBound...]
        let token = tail.split(separator: " ").first.map(String.init) ?? "0"
        let number = Double(token.filter { $0.isNumber || $0 == "." }) ?? 0
        if token.localizedCaseInsensitiveContains("G") {
            return Int64(number * 1_073_741_824)
        }
        if token.localizedCaseInsensitiveContains("M") {
            return Int64(number * 1_048_576)
        }
        return Int64(number)
    }
}

enum BatteryParser {
    static func parsePercent(_ output: String) -> Double? {
        guard let percentIndex = output.firstIndex(of: "%") else { return nil }
        let prefix = output[..<percentIndex]
        let digits = prefix.reversed().prefix { $0.isNumber || $0 == "." }.reversed()
        return Double(String(digits))
    }
}

enum NetworkParser {
    static func parse(_ output: String) -> NetworkSummary {
        var packetsIn: Int64 = 0
        var packetsOut: Int64 = 0
        var bytesIn: Int64 = 0
        var bytesOut: Int64 = 0

        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 10 else { continue }
            let name = String(parts[0])
            guard !name.hasPrefix("lo") else { continue }
            packetsIn += Int64(parts[4]) ?? 0
            bytesIn += Int64(parts[6]) ?? 0
            packetsOut += Int64(parts[7]) ?? 0
            bytesOut += Int64(parts[9]) ?? 0
        }

        return NetworkSummary(packetsIn: packetsIn, packetsOut: packetsOut, bytesIn: bytesIn, bytesOut: bytesOut)
    }
}

enum NetworkInterfaceReader {
    static func read() -> NetworkSummary? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        var packetsIn: UInt64 = 0
        var packetsOut: UInt64 = 0
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaces

        while let pointer = cursor {
            let interface = pointer.pointee
            defer { cursor = interface.ifa_next }
            guard let address = interface.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let dataPointer = interface.ifa_data
            else {
                continue
            }

            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            packetsIn += UInt64(data.ifi_ipackets)
            packetsOut += UInt64(data.ifi_opackets)
            bytesIn += UInt64(data.ifi_ibytes)
            bytesOut += UInt64(data.ifi_obytes)
        }

        return NetworkSummary(
            packetsIn: Int64(clamping: packetsIn),
            packetsOut: Int64(clamping: packetsOut),
            bytesIn: Int64(clamping: bytesIn),
            bytesOut: Int64(clamping: bytesOut)
        )
    }
}

enum DiskActivityReader {
    static func read() -> DiskSummary? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else {
            return nil
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var reads: UInt64 = 0
        var writes: UInt64 = 0
        var readBytes: UInt64 = 0
        var writtenBytes: UInt64 = 0
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let retained = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = retained["Statistics"] as? [String: Any]
            else {
                continue
            }

            reads += uint64Value(statistics["Operations (Read)"])
            writes += uint64Value(statistics["Operations (Write)"])
            readBytes += uint64Value(statistics["Bytes (Read)"])
            writtenBytes += uint64Value(statistics["Bytes (Write)"])
        }

        return DiskSummary(
            reads: Int64(clamping: reads),
            writes: Int64(clamping: writes),
            readBytes: Int64(clamping: readBytes),
            writtenBytes: Int64(clamping: writtenBytes)
        )
    }

    private static func uint64Value(_ value: Any?) -> UInt64 {
        switch value {
        case let number as NSNumber:
            UInt64(truncating: number)
        case let value as UInt64:
            value
        case let value as UInt32:
            UInt64(value)
        case let value as Int:
            value > 0 ? UInt64(value) : 0
        case let value as Int64:
            value > 0 ? UInt64(value) : 0
        default:
            0
        }
    }
}

enum CacheParser {
    static func byteValue(_ output: String, keys: [String]) -> Int64 {
        for key in keys {
            guard let line = output.split(separator: "\n").first(where: { $0.localizedCaseInsensitiveContains(key) }) else {
                continue
            }
            let number = line.split(whereSeparator: { !$0.isNumber }).compactMap { Int64($0) }.first
            return number ?? 0
        }
        return 0
    }
}
