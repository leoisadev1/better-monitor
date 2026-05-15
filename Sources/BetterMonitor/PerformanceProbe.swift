import Foundation

struct PerformanceProbeResult: Equatable {
    let iterations: Int
    let averageSampleDuration: TimeInterval
    let maxSampleDuration: TimeInterval
    let processResidentMemoryBytes: Int64
    let sampledProcessCount: Int
}

enum MonitorPerformanceProbe {
    static func run(iterations: Int = 3, focusedPane: MonitorPane = .cpu, focusedScope: ProcessScope = .all, sampler: any MonitorSampling = SystemMonitorSampler()) async -> PerformanceProbeResult {
        let count = max(1, iterations)
        var durations: [TimeInterval] = []
        var latestProcessCount = 0

        for _ in 0..<count {
            let startedAt = Date()
            let snapshot = await sampler.capture(focusedPane: focusedPane, focusedScope: focusedScope)
            durations.append(Date().timeIntervalSince(startedAt))
            latestProcessCount = snapshot.processes.count
        }

        let total = durations.reduce(0, +)
        let taskInfo = ProcessInfoSampler.taskInfo(pid: getpid())
        return PerformanceProbeResult(
            iterations: count,
            averageSampleDuration: total / Double(count),
            maxSampleDuration: durations.max() ?? 0,
            processResidentMemoryBytes: taskInfo?.residentMemoryBytes ?? 0,
            sampledProcessCount: latestProcessCount
        )
    }
}
