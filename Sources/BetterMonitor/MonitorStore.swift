import Foundation
import Observation

@MainActor
@Observable
final class MonitorSettings {
    var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
            defaults.set(true, forKey: Keys.refreshIntervalV2Migrated)
        }
    }
    var dockIconMode: DockIconMode {
        didSet { defaults.set(dockIconMode.rawValue, forKey: Keys.dockIconMode) }
    }
    var showPrivateAPINotice: Bool {
        didSet { defaults.set(showPrivateAPINotice, forKey: Keys.showPrivateAPINotice) }
    }
    var launchWithAllProcesses: Bool {
        didSet { defaults.set(launchWithAllProcesses, forKey: Keys.launchWithAllProcesses) }
    }
    var visibleColumnsByPane: [MonitorPane: [ProcessColumn]] {
        didSet {
            persistVisibleColumns()
        }
    }
    var columnWidthsByPane: [MonitorPane: [ProcessColumn: Double]] {
        didSet {
            persistColumnWidths()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedRefresh = defaults.object(forKey: Keys.refreshInterval) as? Double
        if defaults.bool(forKey: Keys.refreshIntervalV2Migrated) {
            refreshInterval = savedRefresh.flatMap(RefreshInterval.init(rawValue:)) ?? .normal
        } else if savedRefresh == 2 {
            refreshInterval = .normal
            defaults.set(RefreshInterval.normal.rawValue, forKey: Keys.refreshInterval)
            defaults.set(true, forKey: Keys.refreshIntervalV2Migrated)
        } else {
            refreshInterval = savedRefresh.flatMap(RefreshInterval.init(rawValue:)) ?? .normal
        }
        dockIconMode = DockIconMode(rawValue: defaults.string(forKey: Keys.dockIconMode) ?? "") ?? .appIcon
        showPrivateAPINotice = defaults.object(forKey: Keys.showPrivateAPINotice) as? Bool ?? true
        launchWithAllProcesses = defaults.object(forKey: Keys.launchWithAllProcesses) as? Bool ?? true
        var columnsByPane: [MonitorPane: [ProcessColumn]] = [:]
        let legacySavedColumns = defaults.stringArray(forKey: Keys.legacyVisibleColumns) ?? []
        let legacyColumns = legacySavedColumns.compactMap(ProcessColumn.init(rawValue:))
        let shouldMigratePaneDefaults = !defaults.bool(forKey: Keys.columnDefaultsV2Migrated)
        for pane in MonitorPane.allCases {
            let savedColumns = defaults.stringArray(forKey: Keys.visibleColumns(for: pane)) ?? []
            let columns = savedColumns.compactMap(ProcessColumn.init(rawValue:))
            if columns.isEmpty {
                let defaultColumns = pane == .cpu && !legacyColumns.isEmpty ? legacyColumns : ProcessColumn.defaultVisible(for: pane)
                columnsByPane[pane] = Self.normalizedColumns(defaultColumns)
            } else if shouldMigratePaneDefaults,
                      pane != .cpu,
                      Self.looksLikeLegacyCPUColumns(columns, legacyColumns: legacyColumns) {
                columnsByPane[pane] = Self.normalizedColumns(ProcessColumn.defaultVisible(for: pane))
            } else {
                columnsByPane[pane] = Self.normalizedColumns(columns)
            }
        }
        defaults.set(true, forKey: Keys.columnDefaultsV2Migrated)
        visibleColumnsByPane = columnsByPane
        var widthsByPane: [MonitorPane: [ProcessColumn: Double]] = [:]
        for pane in MonitorPane.allCases {
            let savedWidths = defaults.dictionary(forKey: Keys.columnWidths(for: pane)) as? [String: Double] ?? [:]
            var widths: [ProcessColumn: Double] = [:]
            for column in ProcessColumn.allCases {
                if let width = savedWidths[column.rawValue], width > 0 {
                    widths[column] = width
                }
            }
            widthsByPane[pane] = widths
        }
        columnWidthsByPane = widthsByPane
    }

    var visibleColumns: [ProcessColumn] {
        visibleColumns(for: .cpu)
    }

    func visibleColumns(for pane: MonitorPane) -> [ProcessColumn] {
        Self.normalizedColumns(visibleColumnsByPane[pane] ?? ProcessColumn.defaultVisible(for: pane))
    }

    func isColumnVisible(_ column: ProcessColumn, pane: MonitorPane = .cpu) -> Bool {
        visibleColumns(for: pane).contains(column)
    }

    func setColumn(_ column: ProcessColumn, isVisible: Bool, pane: MonitorPane = .cpu) {
        var columns = visibleColumns(for: pane)
        if isVisible {
            guard !columns.contains(column) else { return }
            columns.append(column)
        } else if column != .name {
            columns.removeAll { $0 == column }
        }
        visibleColumnsByPane[pane] = Self.normalizedColumns(columns)
    }

    func setColumns(_ columns: [ProcessColumn], pane: MonitorPane) {
        visibleColumnsByPane[pane] = Self.normalizedColumns(columns)
    }

    func width(for column: ProcessColumn, pane: MonitorPane) -> Double {
        columnWidthsByPane[pane]?[column] ?? Double(column.width)
    }

    func setWidth(_ width: Double, for column: ProcessColumn, pane: MonitorPane) {
        var widths = columnWidthsByPane[pane] ?? [:]
        widths[column] = max(40, width)
        columnWidthsByPane[pane] = widths
    }

    func resetColumns(for pane: MonitorPane) {
        visibleColumnsByPane[pane] = ProcessColumn.defaultVisible(for: pane)
        columnWidthsByPane[pane] = [:]
    }

    private func persistVisibleColumns() {
        for pane in MonitorPane.allCases {
            defaults.set(visibleColumns(for: pane).map(\.rawValue), forKey: Keys.visibleColumns(for: pane))
        }
    }

    private func persistColumnWidths() {
        for pane in MonitorPane.allCases {
            let rawWidths = (columnWidthsByPane[pane] ?? [:]).reduce(into: [String: Double]()) { partial, element in
                partial[element.key.rawValue] = element.value
            }
            defaults.set(rawWidths, forKey: Keys.columnWidths(for: pane))
        }
    }

    private static func normalizedColumns(_ columns: [ProcessColumn]) -> [ProcessColumn] {
        var unique: [ProcessColumn] = []
        for column in columns where !unique.contains(column) {
            unique.append(column)
        }
        if !unique.contains(.name) {
            unique.insert(.name, at: 0)
        }
        return unique
    }

    private static func looksLikeLegacyCPUColumns(_ columns: [ProcessColumn], legacyColumns: [ProcessColumn]) -> Bool {
        let normalized = normalizedColumns(columns)
        let normalizedLegacy = normalizedColumns(legacyColumns)
        return normalized == ProcessColumn.defaultVisible(for: .cpu)
            || (!normalizedLegacy.isEmpty && normalized == normalizedLegacy)
    }

    private enum Keys {
        static let refreshInterval = "monitor.refreshInterval"
        static let refreshIntervalV2Migrated = "monitor.refreshIntervalV2Migrated"
        static let dockIconMode = "monitor.dockIconMode"
        static let showPrivateAPINotice = "monitor.showPrivateAPINotice"
        static let launchWithAllProcesses = "monitor.launchWithAllProcesses"
        static let legacyVisibleColumns = "monitor.visibleColumns"
        static let columnDefaultsV2Migrated = "monitor.columnDefaultsV2Migrated"

        static func visibleColumns(for pane: MonitorPane) -> String {
            "monitor.visibleColumns.\(pane.rawValue)"
        }

        static func columnWidths(for pane: MonitorPane) -> String {
            "monitor.columnWidths.\(pane.rawValue)"
        }
    }
}

@MainActor
@Observable
final class MonitorStore {
    var selectedPane: MonitorPane = .cpu {
        didSet {
            guard oldValue != selectedPane else { return }
            saveSortPreference(for: oldValue)
            applySortPreference(for: selectedPane)
            scheduleFocusedRefresh()
        }
    }
    var selectedScope: ProcessScope = .all {
        didSet {
            guard oldValue != selectedScope else { return }
            prewarmedPanes.removeAll()
            scheduleFocusedRefresh()
        }
    }
    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            selectVisibleProcessIfNeeded()
        }
    }
    var sortKey: ProcessSortKey = .cpu
    var sortAscending = false
    var selectedProcessID: Int32? {
        didSet {
            if oldValue != selectedProcessID {
                selectedInspection = nil
                selectedOpenFiles = nil
            }
        }
    }
    var snapshot: MonitorSnapshot = .empty
    var history: MonitorHistory = .empty
    var lastRefreshDuration: TimeInterval = 0
    var isRefreshing = false
    var isRunningAction = false
    var lastActionMessage = "Ready"
    var pendingProcessAction: PendingProcessAction?
    var selectedInspection: ProcessInspection?
    var selectedOpenFiles: ProcessOpenFiles?
    var settings: MonitorSettings

    private let sampler: any MonitorSampling
    private var refreshTask: Task<Void, Never>?
    private var focusedRefreshTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var prewarmedPanes = Set<MonitorPane>()
    private var sortPreferencesByPane: [MonitorPane: SortPreference] = [.cpu: SortPreference.default(for: .cpu)]

    init(sampler: any MonitorSampling = SystemMonitorSampler(), settings: MonitorSettings = MonitorSettings()) {
        self.sampler = sampler
        self.settings = settings
        selectedScope = settings.launchWithAllProcesses ? .all : .mine
    }

    var selectedProcess: ProcessSnapshot? {
        snapshot.processes.first { $0.pid == selectedProcessID }
    }

    var currentInspection: ProcessInspection? {
        guard let selectedProcessID, selectedInspection?.pid == selectedProcessID else { return nil }
        return selectedInspection
    }

    var currentOpenFiles: ProcessOpenFiles? {
        guard let selectedProcessID, selectedOpenFiles?.pid == selectedProcessID else { return nil }
        return selectedOpenFiles
    }

    var displayedProcesses: [ProcessSnapshot] {
        let processes = visibleProcesses
        if selectedScope == .allHierarchically {
            return hierarchicalProcesses(from: processes)
        }
        return processes.sorted(by: sort)
    }

    var isShowingSearchFallback: Bool {
        isSearching && filteredProcesses.isEmpty && !scopedProcesses.isEmpty
    }

    func start() async {
        guard refreshTask == nil else { return }
        await refreshNow()
        scheduleBackgroundPrewarm()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = settings.refreshInterval.rawValue
                try? await Task.sleep(for: .seconds(interval))
                await refreshNow()
            }
        }
    }

    func refreshNow() async {
        if isRefreshing { return }
        isRefreshing = true
        let startedAt = ContinuousClock.now
        let next = await sampler.capture(focusedPane: selectedPane, focusedScope: selectedScope)
        let duration = startedAt.duration(to: .now)
        let previous = snapshot == .empty ? nil : snapshot
        lastRefreshDuration = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        if next != snapshot {
            snapshot = next
        }
        prewarmedPanes.insert(selectedPane)
        history.append(snapshot: next, previous: previous, duration: lastRefreshDuration)
        let processIDs = Set(snapshot.processes.map(\.pid))
        if selectedProcessID == nil || selectedProcessID.map({ !processIDs.contains($0) }) == true {
            selectedProcessID = snapshot.processes.first?.pid
        }
        selectVisibleProcessIfNeeded()
        updateDockIcon()
        isRefreshing = false
    }

    func updateDockIcon() {
        DockIconRenderer.update(mode: settings.dockIconMode, snapshot: snapshot, history: history)
    }

    func setSort(_ key: ProcessSortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = Self.defaultAscending(for: key)
        }
        saveSortPreference(for: selectedPane)
    }

    func runSelectedAction(_ action: ProcessAction) async {
        if action == .inspect {
            inspectSelectedProcess()
            return
        }
        if action == .openFilesAndPorts {
            loadOpenFilesAndPorts()
            return
        }
        isRunningAction = true
        lastActionMessage = "Running \(action.displayTitle)..."
        let result = await ProcessDiagnostics.run(action, process: selectedProcess)
        lastActionMessage = result
        isRunningAction = false
    }

    func requestSelectedAction(_ action: ProcessAction) async {
        guard action.requiresConfirmation else {
            await runSelectedAction(action)
            return
        }
        guard let selectedProcess else {
            lastActionMessage = "No process selected."
            return
        }
        pendingProcessAction = PendingProcessAction(action: action, process: selectedProcess)
    }

    func confirmPendingProcessAction() async {
        guard let pendingProcessAction else { return }
        await confirmProcessAction(pendingProcessAction)
    }

    func confirmProcessAction(_ pendingProcessAction: PendingProcessAction) async {
        self.pendingProcessAction = nil
        isRunningAction = true
        lastActionMessage = "Running \(pendingProcessAction.action.displayTitle)..."
        let result = await ProcessDiagnostics.run(pendingProcessAction.action, process: pendingProcessAction.process)
        lastActionMessage = result
        if pendingProcessAction.action == .quit || pendingProcessAction.action == .forceQuit {
            try? await Task.sleep(for: .milliseconds(220))
            await refreshNow()
        }
        isRunningAction = false
    }

    func cancelPendingProcessAction() {
        pendingProcessAction = nil
    }

    func inspectSelectedProcess() {
        guard let selectedProcess else {
            lastActionMessage = "No process selected."
            return
        }
        selectedInspection = ProcessDiagnostics.inspection(for: selectedProcess)
        lastActionMessage = "Inspected \(selectedProcess.name)."
    }

    func loadOpenFilesAndPorts() {
        guard let selectedProcess else {
            lastActionMessage = "No process selected."
            return
        }
        isRunningAction = true
        selectedOpenFiles = ProcessDiagnostics.openFilesAndPorts(for: selectedProcess)
        selectedInspection = selectedInspection ?? ProcessDiagnostics.inspection(for: selectedProcess)
        lastActionMessage = "Loaded open files for \(selectedProcess.name)."
        isRunningAction = false
    }

    private func sort(_ lhs: ProcessSnapshot, _ rhs: ProcessSnapshot) -> Bool {
        let comparison: ComparisonResult
        switch sortKey {
        case .name:
            comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        case .pid:
            comparison = lhs.pid == rhs.pid ? .orderedSame : lhs.pid < rhs.pid ? .orderedAscending : .orderedDescending
        case .user:
            comparison = lhs.user.localizedCaseInsensitiveCompare(rhs.user)
        case .cpu:
            comparison = compare(lhs.cpuPercent, rhs.cpuPercent)
        case .memory:
            comparison = compare(lhs.residentMemoryBytes, rhs.residentMemoryBytes)
        case .energy:
            comparison = compare(lhs.energyImpact, rhs.energyImpact)
        case .disk:
            comparison = compare(lhs.diskReadBytes + lhs.diskWriteBytes, rhs.diskReadBytes + rhs.diskWriteBytes)
        case .diskRead:
            comparison = compare(lhs.diskReadBytes, rhs.diskReadBytes)
        case .diskWritten:
            comparison = compare(lhs.diskWriteBytes, rhs.diskWriteBytes)
        case .network:
            comparison = compare(lhs.networkReceivedBytes + lhs.networkSentBytes, rhs.networkReceivedBytes + rhs.networkSentBytes)
        case .networkReceived:
            comparison = compare(lhs.networkReceivedBytes, rhs.networkReceivedBytes)
        case .networkSent:
            comparison = compare(lhs.networkSentBytes, rhs.networkSentBytes)
        case .state:
            comparison = lhs.state.localizedCaseInsensitiveCompare(rhs.state)
        case .threads:
            comparison = compare(lhs.threadCount, rhs.threadCount)
        case .ports:
            comparison = compareOptional(lhs.portsCount, rhs.portsCount)
        case .preventingSleep:
            comparison = compare(preventingSleepRank(lhs.preventsSleep), preventingSleepRank(rhs.preventsSleep))
        case .wakeups:
            comparison = compareOptional(lhs.wakeups, rhs.wakeups)
        case .cpuTime:
            comparison = compare(cpuTimeCentiseconds(lhs.cpuTime), cpuTimeCentiseconds(rhs.cpuTime))
        }

        if comparison == .orderedSame {
            return lhs.pid < rhs.pid
        }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func saveSortPreference(for pane: MonitorPane) {
        sortPreferencesByPane[pane] = SortPreference(key: sortKey, ascending: sortAscending)
    }

    private func applySortPreference(for pane: MonitorPane) {
        let preference = sortPreferencesByPane[pane] ?? .default(for: pane)
        sortKey = preference.key
        sortAscending = preference.ascending
    }

    private static func defaultAscending(for key: ProcessSortKey) -> Bool {
        [.name, .user, .pid, .state, .cpuTime].contains(key)
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var scopedProcesses: [ProcessSnapshot] {
        let filter = ProcessFilter(query: "", scope: selectedScope, selectedPID: selectedProcessID)
        return snapshot.processes.filter { filter.matches($0) }
    }

    private var filteredProcesses: [ProcessSnapshot] {
        let filter = ProcessFilter(query: searchText, scope: selectedScope, selectedPID: selectedProcessID)
        return snapshot.processes.filter { filter.matches($0) }
    }

    private var visibleProcesses: [ProcessSnapshot] {
        let filtered = filteredProcesses
        let fallback = scopedProcesses
        return filtered.isEmpty && isSearching && !fallback.isEmpty ? fallback : filtered
    }

    private func selectVisibleProcessIfNeeded() {
        let rows = visibleProcesses
        guard let first = rows.first else {
            if selectedProcessID != nil {
                selectedProcessID = nil
            }
            return
        }
        if let selectedProcessID, rows.contains(where: { $0.pid == selectedProcessID }) {
            return
        }
        selectedProcessID = first.pid
    }

    private func scheduleFocusedRefresh() {
        focusedRefreshTask?.cancel()
        focusedRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.refreshNow()
            self?.scheduleBackgroundPrewarm()
        }
    }

    private func scheduleBackgroundPrewarm() {
        guard prewarmTask == nil else { return }
        prewarmTask = Task { [weak self] in
            await self?.prewarmPaneData()
        }
    }

    private func prewarmPaneData() async {
        defer { prewarmTask = nil }
        for pane in MonitorPane.allCases where pane != selectedPane && !prewarmedPanes.contains(pane) {
            if Task.isCancelled { return }
            let next = await sampler.capture(focusedPane: pane, focusedScope: selectedScope)
            mergePrewarmedSnapshot(next, for: pane)
            prewarmedPanes.insert(pane)
        }
    }

    private func mergePrewarmedSnapshot(_ next: MonitorSnapshot, for pane: MonitorPane) {
        guard snapshot != .empty else {
            snapshot = next
            return
        }
        let incomingByPID = Dictionary(uniqueKeysWithValues: next.processes.map { ($0.pid, $0) })
        snapshot.processes = snapshot.processes.map { process in
            guard let incoming = incomingByPID[process.pid] else { return process }
            return process.mergingMetrics(from: incoming, for: pane)
        }
        snapshot.summary = snapshot.summary.merging(next.summary, for: pane)
        snapshot.capturedAt = max(snapshot.capturedAt, next.capturedAt)
    }

    private func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return compare(lhs, rhs)
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedAscending
        case (_?, nil):
            return .orderedDescending
        }
    }

    private func preventingSleepRank(_ value: Bool?) -> Int {
        switch value {
        case true: 2
        case false: 1
        case nil: 0
        }
    }

    private func cpuTimeCentiseconds(_ value: String) -> Int {
        let components = value.split(separator: ":")
        guard let last = components.last else { return 0 }
        let secondsParts = last.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let seconds = Int(secondsParts.first ?? "") ?? 0
        let centiseconds = Int(secondsParts.dropFirst().first ?? "") ?? 0
        let prefix = components.dropLast().compactMap { Int($0) }
        let minutes: Int
        let hours: Int
        if prefix.count >= 2 {
            hours = prefix[prefix.count - 2]
            minutes = prefix[prefix.count - 1]
        } else {
            hours = 0
            minutes = prefix.first ?? 0
        }
        return (((hours * 60) + minutes) * 60 + seconds) * 100 + centiseconds
    }

    private func hierarchicalProcesses(from processes: [ProcessSnapshot]) -> [ProcessSnapshot] {
        let processIDs = Set(processes.map(\.pid))
        let childrenByParent = Dictionary(grouping: processes, by: \.parentPID)
        let roots = processes
            .filter { !processIDs.contains($0.parentPID) || $0.parentPID == $0.pid }
            .sorted(by: sort)
        var visited = Set<Int32>()
        var rows: [ProcessSnapshot] = []

        func append(_ process: ProcessSnapshot, level: Int) {
            guard visited.insert(process.pid).inserted else { return }
            rows.append(process.withHierarchyLevel(level))
            for child in (childrenByParent[process.pid] ?? []).sorted(by: sort) {
                append(child, level: level + 1)
            }
        }

        for root in roots {
            append(root, level: 0)
        }

        for remaining in processes.sorted(by: sort) where !visited.contains(remaining.pid) {
            append(remaining, level: 0)
        }

        return rows
    }
}

private struct SortPreference: Equatable {
    let key: ProcessSortKey
    let ascending: Bool

    static func `default`(for pane: MonitorPane) -> SortPreference {
        SortPreference(key: pane.defaultSortKey, ascending: false)
    }
}
