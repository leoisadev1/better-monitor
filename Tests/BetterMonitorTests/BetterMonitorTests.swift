import Foundation
import Testing
@testable import BetterMonitor

@Test func parsesProcessListRows() async throws {
    let output = """
      42     1 leo              /Applications/Safari.app/Contents/MacOS/Safari  12.5  3.2  204800  4096000 S    1:02.03
      99     1 root             /usr/sbin/syslogd                                0.0  0.1    4096   100000 S    0:01.00
    """

    let processes = ProcessListParser.parsePSOutput(output)

    #expect(processes.count == 2)
    #expect(processes[0].pid == 42)
    #expect(processes[0].name == "Safari")
    #expect(processes[0].residentMemoryBytes == 204_800 * 1024)
    #expect(processes[0].energyImpact > processes[1].energyImpact)
}

@Test func filtersByQueryScopeAndSelection() async throws {
    let mine = ProcessSnapshot.fixture(pid: 7, user: NSUserName(), name: "Better Monitor", cpu: 4)
    let root = ProcessSnapshot.fixture(pid: 1, user: "root", name: "launchd", cpu: 0)
    let other = ProcessSnapshot.fixture(pid: 80, user: "guest", name: "Other", cpu: 0)
    let recentApp = ProcessSnapshot.fixture(pid: 90, user: NSUserName(), name: "Recent App", cpu: 0, hasVisibleWindows: true, launchDate: Date().addingTimeInterval(-60))
    let recentDaemon = ProcessSnapshot.fixture(pid: 91, user: "root", name: "Recent Daemon", cpu: 0, hasVisibleWindows: false, launchDate: Date().addingTimeInterval(-60))
    let oldApp = ProcessSnapshot.fixture(pid: 92, user: NSUserName(), name: "Old App", cpu: 0, hasVisibleWindows: true, launchDate: Date().addingTimeInterval(-13 * 60 * 60))
    let unknownLaunchApp = ProcessSnapshot.fixture(pid: 93, user: NSUserName(), name: "Unknown App", cpu: 0, hasVisibleWindows: true, launchDate: nil)

    #expect(ProcessFilter(query: "better", scope: .all).matches(mine))
    #expect(!ProcessFilter(query: "missing", scope: .all).matches(mine))
    #expect(ProcessFilter(scope: .mine).matches(mine))
    #expect(ProcessFilter(scope: .system).matches(root))
    #expect(ProcessFilter(scope: .otherUsers).matches(other))
    #expect(ProcessFilter(scope: .selected, selectedPID: 7).matches(mine))
    #expect(!ProcessFilter(scope: .selected, selectedPID: 8).matches(mine))
    #expect(ProcessFilter(scope: .lastTwelveHours).matches(recentApp))
    #expect(!ProcessFilter(scope: .lastTwelveHours).matches(recentDaemon))
    #expect(!ProcessFilter(scope: .lastTwelveHours).matches(oldApp))
    #expect(!ProcessFilter(scope: .lastTwelveHours).matches(unknownLaunchApp))
}

@Test func parsesMemoryAndNetworkSummaries() async throws {
    let vm = """
    Mach Virtual Memory Statistics: (page size of 16384 bytes)
    Pages free:                               10.
    Pages speculative:                        20.
    Pages wired down:                         30.
    Pages purgeable:                          40.
    Pages occupied by compressor:             50.
    """

    let values = VMStatParser.parse(vm)
    #expect(values["Pages wired down", default: -1] == Int64(30 * 16_384))
    #expect(values["Pages occupied by compressor", default: -1] == Int64(50 * 16_384))

    let network = """
    Name  Mtu   Network     Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
    en0   1500  <Link#11>   aa:bb:cc              10     0       1000       20     0       3000     0
    lo0   16384 <Link#1>                         999     0        999      999     0        999     0
    """
    let summary = NetworkParser.parse(network)
    #expect(summary.packetsIn == 10)
    #expect(summary.packetsOut == 20)
    #expect(summary.bytesIn == 1000)
    #expect(summary.bytesOut == 3000)
}

@Test func machMemoryReaderCapturesMemoryWithoutShellingOut() async throws {
    let stats = try #require(MachMemoryReader.read())

    #expect(stats.usedBytes > 0)
    #expect(stats.appBytes >= 0)
    #expect(stats.wiredBytes > 0)
    #expect(stats.compressedBytes >= 0)
    #expect(stats.cachedBytes >= 0)
    #expect(stats.swapUsedBytes >= 0)
    #expect(stats.pressure >= 0)
    #expect(stats.pressure <= 1)
}

@Test func networkInterfaceReaderCapturesNetworkCountersWithoutShellingOut() async throws {
    let summary = try #require(NetworkInterfaceReader.read())

    #expect(summary.packetsIn >= 0)
    #expect(summary.packetsOut >= 0)
    #expect(summary.bytesIn >= 0)
    #expect(summary.bytesOut >= 0)
}

@Test func diskActivityReaderCapturesDiskCountersWithoutShellingOut() async throws {
    let summary = try #require(DiskActivityReader.read())

    #expect(summary.reads >= 0)
    #expect(summary.writes >= 0)
    #expect(summary.readBytes >= 0)
    #expect(summary.writtenBytes >= 0)
}

@Test func powerReadersCaptureEnergyStateWithoutShellingOut() async throws {
    let assertions = try #require(PowerAssertionReader.preventingSleepPIDs())
    let power = PowerSourceReader.read()

    #expect(assertions.count >= 0)
    if let power {
        #expect(!power.source.isEmpty)
        #expect((power.batteryPercent ?? 0) >= 0)
    }
}

@Test func windowOwnershipReaderCapturesVisibleWindowOwnersWithoutShellingOut() async throws {
    let pids = WindowOwnershipReader.visibleWindowPIDs()

    #expect(pids.allSatisfy { $0 > 0 })
}

@Test func parsesPerProcessNetworkSamples() async throws {
    let output = """
    ,bytes_in,bytes_out,
    launchd.1,10,20,
    Helium Helper.96703,108956812,582879611,
    com.apple.some.daemon.42,5,7,
    malformed,nope,1,
    """

    let samples = PerProcessNetworkParser.parse(output)

    #expect(samples[1]?.bytesIn == 10)
    #expect(samples[1]?.bytesOut == 20)
    #expect(samples[96703]?.bytesIn == 108_956_812)
    #expect(samples[96703]?.bytesOut == 582_879_611)
    #expect(samples[42]?.bytesIn == 5)
    #expect(samples[42]?.bytesOut == 7)
    #expect(samples.count == 3)
}

@Test func parsesSleepPreventingAssertions() async throws {
    let output = """
    Listed by owning process:
       pid 99(powerd): [0x0000000100018001] 00:05:12 PreventUserIdleSystemSleep named: "com.apple.powermanagement"
       pid 42(Backup): [0x0000000100018002] 00:00:11 NoIdleSleepAssertion named: "backup"
       pid nope: PreventUserIdleSystemSleep
       pid 123(caffeinate): PreventSystemSleep
    """

    let pids = SleepAssertionParser.parse(output)

    #expect(pids == [99, 123])
}

@Test func formatsMonitoringValues() async throws {
    #expect(MonitorFormatting.percent(9.876) == "9.88%")
    #expect(MonitorFormatting.percent(25.25) == "25.2%")
    #expect(MonitorFormatting.percent(125.25) == "125%")
    #expect(MonitorFormatting.bytes(1_048_576).contains("MB"))
}

@Test func formatsProcessColumnValues() async throws {
    let process = ProcessSnapshot.fixture(pid: 123, user: "leo", name: "Better Monitor", cpu: 12.5, diskReadBytes: 1_024, diskWriteBytes: 2_048, networkReceivedBytes: 4_096, networkSentBytes: 8_192)

    #expect(ProcessColumnValue.string(for: .name, process: process) == "Better Monitor")
    #expect(ProcessColumnValue.string(for: .pid, process: process) == "123")
    #expect(ProcessColumnValue.string(for: .cpu, process: process) == "12.5%")
    #expect(ProcessColumnValue.string(for: .diskRead, process: process).contains("/s"))
    #expect(ProcessColumnValue.string(for: .diskWritten, process: process).contains("/s"))
    #expect(ProcessColumnValue.string(for: .networkReceived, process: process).contains("KB"))
    #expect(ProcessColumnValue.string(for: .networkSent, process: process).contains("KB"))
    #expect(ProcessColumnValue.string(for: .threads, process: process) == "1")
    #expect(ProcessColumnValue.string(for: .ports, process: process) == "—")
    #expect(ProcessColumnValue.string(for: .preventingSleep, process: process) == "—")
    #expect(ProcessColumnValue.string(for: .wakeups, process: process) == "—")
    #expect(ProcessColumnValue.string(for: .cpuTime, process: process) == "0:00.00")
}

@Test func samplerCapturesLiveProcesses() async throws {
    let snapshot = await SystemMonitorSampler().capture()

    #expect(!snapshot.processes.isEmpty)
    #expect(snapshot.summary.cpu.processCount == snapshot.processes.count)
    #expect(snapshot.summary.memory.physicalMemoryBytes > 0)
    #expect(snapshot.processes.contains { $0.threadCount > 0 })
    #expect(snapshot.processes.contains { $0.networkReceivedBytes >= 0 && $0.networkSentBytes >= 0 })
}

@Test func networkPaneCanEnrichLiveProcessNetworkCounters() async throws {
    let snapshot = await SystemMonitorSampler().capture(focusedPane: .network)

    #expect(!snapshot.processes.isEmpty)
    #expect(snapshot.summary.network.bytesIn >= 0)
    #expect(snapshot.summary.network.bytesOut >= 0)
}

@Test func performanceProbeProducesUsableTelemetry() async throws {
    let result = await MonitorPerformanceProbe.run(iterations: 2)

    if ProcessInfo.processInfo.environment["BETTER_MONITOR_PRINT_PROBE"] == "1" {
        print("BETTER_MONITOR_PROBE iterations=\(result.iterations) avg_ms=\(String(format: "%.3f", result.averageSampleDuration * 1_000)) max_ms=\(String(format: "%.3f", result.maxSampleDuration * 1_000)) rss_bytes=\(result.processResidentMemoryBytes) processes=\(result.sampledProcessCount)")
    }

    #expect(result.iterations == 2)
    #expect(result.sampledProcessCount > 0)
    #expect(result.averageSampleDuration > 0)
    #expect(result.maxSampleDuration >= result.averageSampleDuration)
    #expect(result.processResidentMemoryBytes > 0)
}

@MainActor
@Test func storeSortsWithStableTieBreaks() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(
        capturedAt: Date(),
        processes: [
            .fixture(pid: 2, user: "leo", name: "B", cpu: 5),
            .fixture(pid: 1, user: "leo", name: "A", cpu: 5),
            .fixture(pid: 3, user: "leo", name: "C", cpu: 9)
        ],
        summary: .empty
    )))
    await store.refreshNow()

    store.sortKey = .cpu
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [3, 1, 2])

    store.sortAscending = true
    #expect(store.displayedProcesses.map(\.pid) == [1, 2, 3])
}

@MainActor
@Test func storeKeepsTableUsableWhenSearchHasNoMatches() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(
        capturedAt: Date(),
        processes: [
            .fixture(pid: 1, user: "leo", name: "Alpha", cpu: 2),
            .fixture(pid: 2, user: "leo", name: "Beta", cpu: 1)
        ],
        summary: .empty
    )))
    await store.refreshNow()

    store.searchText = "definitely-no-match"

    #expect(store.isShowingSearchFallback)
    #expect(store.displayedProcesses.map(\.pid) == [1, 2])
}

@MainActor
@Test func storeSelectionFollowsSearchResults() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(
        capturedAt: Date(),
        processes: [
            .fixture(pid: 1, user: "leo", name: "Alpha", cpu: 2),
            .fixture(pid: 2, user: "leo", name: "Beta", cpu: 1)
        ],
        summary: .empty
    )))
    await store.refreshNow()

    store.selectedProcessID = 1
    store.searchText = "Beta"

    #expect(store.selectedProcessID == 2)
    #expect(store.displayedProcesses.map(\.pid) == [2])
}

@MainActor
@Test func storeReplacesStaleSelectionAfterRefresh() async throws {
    let sampler = SequenceSampler(snapshots: [
        MonitorSnapshot(
            capturedAt: Date(),
            processes: [
                .fixture(pid: 10, user: "leo", name: "Gone", cpu: 2),
                .fixture(pid: 20, user: "leo", name: "Still Here", cpu: 1)
            ],
            summary: .empty
        ),
        MonitorSnapshot(
            capturedAt: Date(),
            processes: [
                .fixture(pid: 20, user: "leo", name: "Still Here", cpu: 1)
            ],
            summary: .empty
        )
    ])
    let store = MonitorStore(sampler: sampler)

    await store.refreshNow()
    store.selectedProcessID = 10
    await store.refreshNow()

    #expect(store.selectedProcessID == 20)
    #expect(store.displayedProcesses.map(\.pid) == [20])
}

@MainActor
@Test func storeSortsActivityMonitorStyleDetailColumns() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(
        capturedAt: Date(),
        processes: [
            .fixture(pid: 1, user: "leo", name: "A", cpu: 0, state: "S", cpuTime: "0:03.00", threadCount: 2, portsCount: nil, preventsSleep: false, wakeups: 8, diskReadBytes: 10, diskWriteBytes: 50, networkReceivedBytes: 25, networkSentBytes: 15),
            .fixture(pid: 2, user: "leo", name: "B", cpu: 0, state: "R", cpuTime: "1:00.00", threadCount: 8, portsCount: 9, preventsSleep: true, wakeups: 15, diskReadBytes: 40, diskWriteBytes: 20, networkReceivedBytes: 60, networkSentBytes: 90),
            .fixture(pid: 3, user: "leo", name: "C", cpu: 0, state: "T", cpuTime: "0:10.00", threadCount: 4, portsCount: 3, preventsSleep: nil, wakeups: nil, diskReadBytes: 100, diskWriteBytes: 5, networkReceivedBytes: 5, networkSentBytes: 40)
        ],
        summary: .empty
    )))
    await store.refreshNow()

    store.sortKey = .threads
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [2, 3, 1])

    store.sortKey = .ports
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [2, 3, 1])

    store.sortKey = .preventingSleep
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [2, 1, 3])

    store.sortKey = .wakeups
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [2, 1, 3])

    store.sortKey = .cpuTime
    store.sortAscending = true
    #expect(store.displayedProcesses.map(\.pid) == [1, 3, 2])

    store.sortKey = .diskRead
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [3, 2, 1])

    store.sortKey = .diskWritten
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [1, 2, 3])

    store.sortKey = .networkReceived
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [2, 1, 3])

    store.sortKey = .networkSent
    store.sortAscending = false
    #expect(store.displayedProcesses.map(\.pid) == [2, 3, 1])
}

@MainActor
@Test func storeKeepsPaneSpecificSortPreferences() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: .empty))

    #expect(store.selectedPane == .cpu)
    #expect(store.sortKey == .cpu)
    #expect(!store.sortAscending)

    store.setSort(.name)
    #expect(store.sortKey == .name)
    #expect(store.sortAscending)

    store.selectedPane = .memory
    #expect(store.sortKey == .memory)
    #expect(!store.sortAscending)

    store.setSort(.user)
    #expect(store.sortKey == .user)
    #expect(store.sortAscending)

    store.selectedPane = .cpu
    #expect(store.sortKey == .name)
    #expect(store.sortAscending)

    store.selectedPane = .network
    #expect(store.sortKey == .network)
    #expect(!store.sortAscending)

    store.selectedPane = .memory
    #expect(store.sortKey == .user)
    #expect(store.sortAscending)
}

@MainActor
@Test func paneSwitchingDoesNotCaptureImmediately() async throws {
    let sampler = CountingSampler(snapshot: .empty)
    let store = MonitorStore(sampler: sampler)

    await store.refreshNow()
    store.selectedPane = .memory
    store.selectedPane = .energy
    store.selectedPane = .disk
    try? await Task.sleep(for: .milliseconds(180))

    #expect(await sampler.captureCount() == 1)
    #expect(store.selectedPane == .disk)
}

@MainActor
@Test func storeCanDisplayProcessHierarchy() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(
        capturedAt: Date(),
        processes: [
            .fixture(pid: 20, parentPID: 10, user: "leo", name: "Child", cpu: 2),
            .fixture(pid: 10, parentPID: 1, user: "leo", name: "Parent", cpu: 1),
            .fixture(pid: 30, parentPID: 20, user: "leo", name: "Grandchild", cpu: 3)
        ],
        summary: .empty
    )))
    await store.refreshNow()

    store.selectedScope = .allHierarchically
    store.sortKey = .name
    store.sortAscending = true

    let rows = store.displayedProcesses
    #expect(rows.map(\.pid) == [10, 20, 30])
    #expect(rows.map(\.hierarchyLevel) == [0, 1, 2])
}

@MainActor
@Test func storeHonorsLaunchScopePreference() async throws {
    let suiteName = "better-monitor-launch-scope-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(false, forKey: "monitor.launchWithAllProcesses")
    let mineSettings = MonitorSettings(defaults: defaults)
    let mineStore = MonitorStore(sampler: FixtureSampler(snapshot: .empty), settings: mineSettings)
    #expect(mineStore.selectedScope == .mine)

    defaults.set(true, forKey: "monitor.launchWithAllProcesses")
    let allSettings = MonitorSettings(defaults: defaults)
    let allStore = MonitorStore(sampler: FixtureSampler(snapshot: .empty), settings: allSettings)
    #expect(allStore.selectedScope == .all)
}

@MainActor
@Test func storeRequestsConfirmationForDestructiveProcessActions() async throws {
    let process = ProcessSnapshot.fixture(pid: 777, user: "leo", name: "Danger App", cpu: 0)
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(capturedAt: Date(), processes: [process], summary: .empty)))
    await store.refreshNow()

    await store.requestSelectedAction(.quit)

    #expect(store.pendingProcessAction?.action == .quit)
    #expect(store.pendingProcessAction?.process.pid == 777)
    #expect(ProcessAction.quit.confirmationButtonTitle == "Quit")
    #expect(ProcessAction.quit.confirmationTitle(for: process).contains("Danger App"))
    #expect(ProcessAction.forceQuit.requiresConfirmation)
    #expect(ProcessAction.sendInterrupt.requiresConfirmation)
    #expect(!ProcessAction.inspect.requiresConfirmation)
    #expect(!ProcessAction.openFilesAndPorts.requiresConfirmation)
    #expect(!ProcessAction.openFileLocation.requiresConfirmation)

    store.cancelPendingProcessAction()

    #expect(store.pendingProcessAction == nil)
}

@MainActor
@Test func storeLoadsSelectedProcessInspectionInline() async throws {
    let process = ProcessSnapshot.fixture(pid: getpid(), user: NSUserName(), name: "better-monitorPackageTests", cpu: 0)
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(capturedAt: Date(), processes: [process], summary: .empty)))
    await store.refreshNow()

    store.inspectSelectedProcess()

    #expect(store.currentInspection?.pid == getpid())
    #expect(store.currentInspection?.executablePath?.isEmpty == false)
    #expect(store.lastActionMessage.contains("Inspected"))
}

@MainActor
@Test func storeReportsMissingSelectionBeforeDestructiveActionConfirmation() async throws {
    let store = MonitorStore(sampler: FixtureSampler(snapshot: MonitorSnapshot(capturedAt: Date(), processes: [], summary: .empty)))
    await store.refreshNow()

    await store.requestSelectedAction(.forceQuit)

    #expect(store.pendingProcessAction == nil)
    #expect(store.lastActionMessage == "No process selected.")
}

@MainActor
@Test func processDiagnosticsCanQuitAndForceQuitOwnedProcesses() async throws {
    let quitProcess = try launchSleepProcess()
    let quitSnapshot = ProcessSnapshot.fixture(pid: Int32(quitProcess.processIdentifier), user: NSUserName(), name: "sleep", cpu: 0)

    let quitResult = await ProcessDiagnostics.run(.quit, process: quitSnapshot)
    quitProcess.waitUntilExit()

    #expect(!quitProcess.isRunning)
    #expect(quitResult.contains("Quit") || quitResult.contains("Sent TERM"))

    let forceQuitProcess = try launchSleepProcess()
    let forceQuitSnapshot = ProcessSnapshot.fixture(pid: Int32(forceQuitProcess.processIdentifier), user: NSUserName(), name: "sleep", cpu: 0)

    let forceQuitResult = await ProcessDiagnostics.run(.forceQuit, process: forceQuitSnapshot)
    forceQuitProcess.waitUntilExit()

    #expect(!forceQuitProcess.isRunning)
    #expect(forceQuitResult.contains("Force quit") || forceQuitResult.contains("Sent KILL"))
}

@Test func processInfoSamplerReadsCurrentTaskInfo() async throws {
    let pid = getpid()
    let task = ProcessInfoSampler.taskInfo(pid: pid)
    let rusage = ProcessInfoSampler.rusage(pid: pid)
    let liveProcessList = ProcessInfoSampler.allBSDInfos()
    let path = ProcessInfoSampler.path(pid: pid)

    #expect(task?.threadCount ?? 0 > 0)
    #expect(task?.residentMemoryBytes ?? 0 > 0)
    #expect(rusage != nil)
    #expect(rusage?.physicalFootprintBytes ?? 0 > 0)
    #expect(rusage?.residentSizeBytes ?? 0 > 0)
    #expect(rusage?.wakeups ?? -1 >= 0)
    #expect(liveProcessList.contains { $0.pid == pid })
    #expect(path?.isEmpty == false)
}

@MainActor
@Test func inspectResolvesExecutablePathLazily() async throws {
    let process = ProcessSnapshot.fixture(pid: getpid(), user: NSUserName(), name: "better-monitorPackageTests", cpu: 0)

    let output = ProcessDiagnostics.inspect(process)

    #expect(output.contains("Executable Path:"))
    #expect(output.contains("better-monitorPackageTests"))
}

@Test func energyImpactUsesLiveResourceRatesInsteadOfCumulativeTotals() async throws {
    let first = SystemMonitorSampler.energyImpact(
        cpuPercent: 2,
        memoryPercent: 5,
        counters: ProcessResourceCounters(readBytes: 0, writtenBytes: 0, energyNanojoules: 9_000_000_000_000, wakeups: 10_000_000),
        previousCounters: nil,
        elapsedSeconds: nil
    )
    let second = SystemMonitorSampler.energyImpact(
        cpuPercent: 2,
        memoryPercent: 5,
        counters: ProcessResourceCounters(readBytes: 0, writtenBytes: 0, energyNanojoules: 9_001_000_000_000, wakeups: 10_000_250),
        previousCounters: ProcessResourceCounters(readBytes: 0, writtenBytes: 0, energyNanojoules: 9_000_000_000_000, wakeups: 10_000_000),
        elapsedSeconds: 2
    )

    #expect(first < 5)
    #expect(second > first)
    #expect(second < 10)
}

@Test func energyPaneReportsBoundedLiveImpact() async throws {
    let sampler = SystemMonitorSampler()
    _ = await sampler.capture(focusedPane: .energy, focusedScope: .all)
    try? await Task.sleep(for: .milliseconds(160))

    let snapshot = await sampler.capture(focusedPane: .energy, focusedScope: .all)
    let impacts = snapshot.processes.map(\.energyImpact)

    #expect(!impacts.isEmpty)
    #expect(impacts.allSatisfy { $0 >= 0 && $0 <= 100 })
    #expect(snapshot.summary.energy.averageImpact >= 0)
    #expect(snapshot.summary.energy.averageImpact <= 100)
}

@Test func hostCPUReaderComputesDeltaPercentages() async throws {
    let previous = HostCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
    let current = HostCPUTicks(user: 130, system: 70, idle: 950, nice: 0)
    let percentages = HostCPUReader.percentages(current: current, previous: previous)

    #expect(abs(percentages.user - 20) < 0.001)
    #expect(abs(percentages.system - 13.333) < 0.01)
    #expect(abs(percentages.idle - 66.667) < 0.01)
}

@Test func monitorHistoryKeepsBoundedPaneSeries() async throws {
    var history = MonitorHistory.empty
    let first = MonitorSnapshot(capturedAt: Date(timeIntervalSince1970: 1), processes: [], summary: SystemSummary(
        cpu: CPUSummary(userPercent: 10, systemPercent: 5, idlePercent: 85, processCount: 1, threadCount: 1, loadAverage: []),
        memory: MemorySummary(physicalMemoryBytes: 100, usedBytes: 50, appBytes: 20, wiredBytes: 10, compressedBytes: 5, cachedBytes: 15, swapUsedBytes: 0, pressure: 0.5),
        energy: EnergySummary(totalImpact: 300, averageImpact: 3, batteryPercent: nil, powerSource: "AC", preventingSleepCount: 0),
        disk: DiskSummary(reads: 10, writes: 20, readBytes: 100, writtenBytes: 100),
        network: NetworkSummary(packetsIn: 40, packetsOut: 60, bytesIn: 200, bytesOut: 100),
        cache: CacheSummary(isAvailable: true, isActive: true, servedBytes: 0, droppedBytes: 0, originBytes: 0, peerBytes: 0, pressure: 0.25)
    ))
    let second = MonitorSnapshot(capturedAt: Date(timeIntervalSince1970: 3), processes: [], summary: SystemSummary(
        cpu: CPUSummary(userPercent: 20, systemPercent: 10, idlePercent: 70, processCount: 1, threadCount: 1, loadAverage: []),
        memory: first.summary.memory,
        energy: first.summary.energy,
        disk: DiskSummary(reads: 16, writes: 24, readBytes: 300, writtenBytes: 300),
        network: NetworkSummary(packetsIn: 52, packetsOut: 66, bytesIn: 800, bytesOut: 500),
        cache: first.summary.cache
    ))

    history.append(snapshot: first, previous: nil, duration: 0.1, limit: 2)
    history.append(snapshot: second, previous: first, duration: 0.2, limit: 2)
    history.append(snapshot: second, previous: second, duration: 0.3, limit: 2)

    #expect(history.values(for: .cpu) == [30, 30])
    #expect(history.values(for: .energy) == [3, 3])
    #expect(history.diskReadsPerSecond == [3, 0])
    #expect(history.diskWritesPerSecond == [2, 0])
    #expect(history.diskReadBytesPerSecond == [100, 0])
    #expect(history.diskWrittenBytesPerSecond == [100, 0])
    #expect(history.diskBytesPerSecond == [200, 0])
    #expect(history.networkPacketsInPerSecond == [6, 0])
    #expect(history.networkPacketsOutPerSecond == [3, 0])
    #expect(history.networkBytesInPerSecond == [300, 0])
    #expect(history.networkBytesOutPerSecond == [200, 0])
    #expect(history.networkBytesPerSecond == [500, 0])
    #expect(history.sampleDurations == [200, 300])
}

@MainActor
@Test func settingsPersistColumnChoices() async throws {
    let suiteName = "better-monitor-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = MonitorSettings(defaults: defaults)
    settings.refreshInterval = .fast
    settings.dockIconMode = .cpuHistory
    settings.setColumn(.threads, isVisible: true)
    settings.setColumn(.network, isVisible: false)
    settings.setColumn(.ports, isVisible: true, pane: .memory)
    settings.setColumn(.cpu, isVisible: false, pane: .memory)
    settings.setColumns([.name, .pid, .cpu], pane: .cpu)
    settings.setWidth(320, for: .name, pane: .cpu)
    settings.setWidth(140, for: .memory, pane: .memory)

    let reloaded = MonitorSettings(defaults: defaults)
    #expect(reloaded.refreshInterval == .fast)
    #expect(reloaded.dockIconMode == .cpuHistory)
    #expect(!reloaded.isColumnVisible(.threads))
    #expect(!reloaded.isColumnVisible(.network))
    #expect(reloaded.isColumnVisible(.name))
    #expect(reloaded.isColumnVisible(.ports, pane: .memory))
    #expect(!reloaded.isColumnVisible(.cpu, pane: .memory))
    #expect(reloaded.isColumnVisible(.cpu, pane: .cpu))
    #expect(reloaded.visibleColumns(for: .cpu) == [.name, .pid, .cpu])
    #expect(reloaded.width(for: .name, pane: .cpu) == 320)
    #expect(reloaded.width(for: .memory, pane: .memory) == 140)
}

@MainActor
@Test func settingsResetPaneColumnsAndWidths() async throws {
    let suiteName = "better-monitor-reset-columns-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = MonitorSettings(defaults: defaults)
    settings.setColumns([.name, .pid], pane: .energy)
    settings.setWidth(320, for: .name, pane: .energy)

    settings.resetColumns(for: .energy)

    let reloaded = MonitorSettings(defaults: defaults)
    #expect(reloaded.visibleColumns(for: .energy) == ProcessColumn.defaultVisible(for: .energy))
    #expect(reloaded.width(for: .name, pane: .energy) == Double(ProcessColumn.name.width))
}

@MainActor
@Test func settingsMigratesLegacyCPUColumnsAwayFromOtherPanes() async throws {
    let suiteName = "better-monitor-legacy-pane-columns-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let legacyCPUColumns = ProcessColumn.defaultVisible(for: .cpu).map(\.rawValue)
    defaults.set(legacyCPUColumns, forKey: "monitor.visibleColumns")
    for pane in MonitorPane.allCases where pane != .cpu {
        defaults.set(legacyCPUColumns, forKey: "monitor.visibleColumns.\(pane.rawValue)")
    }

    let settings = MonitorSettings(defaults: defaults)

    #expect(settings.visibleColumns(for: .cpu) == ProcessColumn.defaultVisible(for: .cpu))
    #expect(settings.visibleColumns(for: .memory) == ProcessColumn.defaultVisible(for: .memory))
    #expect(settings.visibleColumns(for: .energy) == ProcessColumn.defaultVisible(for: .energy))
    #expect(settings.visibleColumns(for: .disk) == ProcessColumn.defaultVisible(for: .disk))
    #expect(settings.visibleColumns(for: .network) == ProcessColumn.defaultVisible(for: .network))
}

@MainActor
@Test func settingsMigratesOldNormalRefreshInterval() async throws {
    let suiteName = "better-monitor-refresh-migration-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(2.0, forKey: "monitor.refreshInterval")

    let settings = MonitorSettings(defaults: defaults)

    #expect(settings.refreshInterval == .fast)
    #expect(defaults.double(forKey: "monitor.refreshInterval") == RefreshInterval.fast.rawValue)
}

private struct FixtureSampler: MonitorSampling {
    let snapshot: MonitorSnapshot

    func capture(focusedPane: MonitorPane, focusedScope: ProcessScope) async -> MonitorSnapshot {
        snapshot
    }
}

private func launchSleepProcess() throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    try process.run()
    return process
}

private actor SequenceSampler: MonitorSampling {
    private let snapshots: [MonitorSnapshot]
    private var index = 0

    init(snapshots: [MonitorSnapshot]) {
        self.snapshots = snapshots
    }

    func capture(focusedPane: MonitorPane, focusedScope: ProcessScope) async -> MonitorSnapshot {
        guard !snapshots.isEmpty else { return .empty }
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
}

private actor CountingSampler: MonitorSampling {
    private let snapshot: MonitorSnapshot
    private var count = 0

    init(snapshot: MonitorSnapshot) {
        self.snapshot = snapshot
    }

    func capture(focusedPane: MonitorPane, focusedScope: ProcessScope) async -> MonitorSnapshot {
        count += 1
        return snapshot
    }

    func captureCount() -> Int {
        count
    }
}

private extension ProcessSnapshot {
    static func fixture(
        pid: Int32,
        parentPID: Int32 = 1,
        user: String,
        name: String,
        cpu: Double,
        state: String? = nil,
        cpuTime: String = "0:00.00",
        threadCount: Int = 1,
        portsCount: Int? = nil,
        preventsSleep: Bool? = nil,
        wakeups: Int64? = nil,
        diskReadBytes: Int64 = 0,
        diskWriteBytes: Int64 = 0,
        networkReceivedBytes: Int64 = 0,
        networkSentBytes: Int64 = 0,
        hasVisibleWindows: Bool = false,
        launchDate: Date? = nil
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            parentPID: parentPID,
            user: user,
            command: "/bin/\(name)",
            name: name,
            cpuPercent: cpu,
            memoryPercent: 1,
            residentMemoryBytes: 1024,
            virtualMemoryBytes: 2048,
            state: state ?? (cpu > 0 ? "R" : "S"),
            cpuTime: cpuTime,
            threadCount: threadCount,
            portsCount: portsCount,
            preventsSleep: preventsSleep,
            wakeups: wakeups,
            energyImpact: cpu,
            diskReadBytes: diskReadBytes,
            diskWriteBytes: diskWriteBytes,
            networkReceivedBytes: networkReceivedBytes,
            networkSentBytes: networkSentBytes,
            hasVisibleWindows: hasVisibleWindows,
            usesGPU: false,
            launchDate: launchDate
        )
    }
}
