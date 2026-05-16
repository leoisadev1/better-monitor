import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: MonitorStore

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            PaneSidebar(store: store)
                .frame(width: 220)
                .frame(maxHeight: .infinity)
            Divider()

            VStack(spacing: 0) {
                MonitorToolbar(store: store)
                Divider()
                SummaryStrip(snapshot: store.snapshot, history: store.history, selectedPane: store.selectedPane)
                ProcessTable(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatusBar(store: store)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.settings.dockIconMode) {
            store.updateDockIcon()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refreshNow() }
        }
        .alert(processActionAlertTitle, isPresented: processActionConfirmationBinding) {
            if let pending = store.pendingProcessAction {
                Button(pending.action.confirmationButtonTitle, role: .destructive) {
                    Task { await store.confirmProcessAction(pending) }
                }
            }
            Button("Cancel", role: .cancel) {
                store.cancelPendingProcessAction()
            }
        } message: {
            Text(processActionAlertMessage)
        }
    }

    private var processActionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.pendingProcessAction != nil },
            set: { isPresented in
                if !isPresented, store.pendingProcessAction != nil {
                    store.cancelPendingProcessAction()
                }
            }
        )
    }

    private var processActionAlertTitle: String {
        guard let pending = store.pendingProcessAction else { return "Confirm Process Action" }
        return pending.action.confirmationTitle(for: pending.process)
    }

    private var processActionAlertMessage: String {
        guard let pending = store.pendingProcessAction else { return "" }
        return pending.action.confirmationMessage(for: pending.process)
    }
}

private struct PaneSidebar: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monitor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 26)

            VStack(spacing: 3) {
                ForEach(MonitorPane.allCases) { pane in
                    Button {
                        store.selectedPane = pane
                    } label: {
                        PaneSidebarRow(
                            pane: pane,
                            value: sidebarValue(for: pane),
                            shortcut: "⌘\(pane.keyboardEquivalent)",
                            isSelected: store.selectedPane == pane
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Show \(pane.title)")
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            SidebarProcessSummary(store: store)
                .padding(8)
        }
        .background(.bar)
    }

    private func sidebarValue(for pane: MonitorPane) -> String {
        switch pane {
        case .cpu:
            let cpu = store.snapshot.summary.cpu.userPercent + store.snapshot.summary.cpu.systemPercent
            return MonitorFormatting.percent(cpu)
        case .memory:
            return "\(MonitorFormatting.bytes(store.snapshot.summary.memory.usedBytes)) used"
        case .energy:
            return String(format: "%.1f avg", store.snapshot.summary.energy.averageImpact)
        case .disk:
            return MonitorFormatting.rate(store.history.diskBytesPerSecond.last ?? 0)
        case .network:
            return MonitorFormatting.rate(store.history.networkBytesPerSecond.last ?? 0)
        case .cache:
            return store.snapshot.summary.cache.isAvailable ? "Available" : "Off"
        }
    }
}

private struct PaneSidebarRow: View {
    let pane: MonitorPane
    let value: String
    let shortcut: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(shortcut)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.68))
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 7))
    }
}

private struct SidebarProcessSummary: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let process = store.selectedProcess {
                HStack(alignment: .center, spacing: 8) {
                    Image(nsImage: ProcessIconProvider.icon(for: process))
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(.rect(cornerRadius: 5))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(process.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("PID \(process.pid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                    GridRow {
                        Text("CPU")
                            .foregroundStyle(.secondary)
                        Text(MonitorFormatting.percent(process.cpuPercent))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Memory")
                            .foregroundStyle(.secondary)
                        Text(MonitorFormatting.bytes(process.residentMemoryBytes))
                            .monospacedDigit()
                    }
                }
                .font(.caption2)

                HStack(spacing: 6) {
                    Button("Quit") {
                        Task { await store.requestSelectedAction(.quit) }
                    }
                    Button("Force Quit") {
                        Task { await store.requestSelectedAction(.forceQuit) }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isRunningAction)
            } else {
                Text("Select a process")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }
}

private struct MonitorToolbar: View {
    @Bindable var store: MonitorStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(store.selectedPane.title, systemImage: store.selectedPane.systemImage)
                    .font(.headline)
                    .frame(minWidth: 132, alignment: .leading)

                ProcessSearchField(store: store)
                    .frame(minWidth: 260, idealWidth: 380, maxWidth: 520)

                Picker("Scope", selection: $store.selectedScope) {
                    ForEach(ProcessScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .frame(width: 220)

                Spacer(minLength: 12)

                Button {
                    Task { await store.refreshNow() }
                } label: {
                    Label("Refresh", systemImage: store.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help("Refresh Now")
                .disabled(store.isRefreshing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }
}

private struct ProcessSearchField: View {
    @Bindable var store: MonitorStore
    @State private var draft = ""
    @State private var pendingSearchTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search processes", text: $draft)
                .textFieldStyle(.plain)
            if !draft.isEmpty {
                Button {
                    draft = ""
                    pendingSearchTask?.cancel()
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .onAppear {
            draft = store.searchText
        }
        .onChange(of: draft) { _, newValue in
            pendingSearchTask?.cancel()
            pendingSearchTask = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    store.searchText = newValue
                }
            }
        }
    }
}

private struct SummaryStrip: View {
    let snapshot: MonitorSnapshot
    let history: MonitorHistory
    let selectedPane: MonitorPane

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(cards) { card in
                    MetricCard(card: card)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            MiniGraph(values: graphValues, tint: tint)
                .frame(height: 42)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var cards: [MetricCardModel] {
        switch selectedPane {
        case .cpu:
            let cpu = snapshot.summary.cpu
            return [
                MetricCardModel(title: "System", value: MonitorFormatting.percent(cpu.systemPercent), color: .red),
                MetricCardModel(title: "User", value: MonitorFormatting.percent(cpu.userPercent), color: .blue),
                MetricCardModel(title: "Idle", value: MonitorFormatting.percent(cpu.idlePercent), color: .gray),
                MetricCardModel(title: "Processes", value: "\(cpu.processCount)", color: .secondary),
                MetricCardModel(title: "Threads", value: "\(cpu.threadCount)", color: .secondary)
            ]
        case .memory:
            let memory = snapshot.summary.memory
            return [
                MetricCardModel(title: "Pressure", value: memoryPressureLabel(memory.pressure), color: memoryPressureColor(memory.pressure)),
                MetricCardModel(title: "Used", value: MonitorFormatting.bytes(memory.usedBytes), color: .blue),
                MetricCardModel(title: "App Memory", value: MonitorFormatting.bytes(memory.appBytes), color: .purple),
                MetricCardModel(title: "Wired", value: MonitorFormatting.bytes(memory.wiredBytes), color: .orange),
                MetricCardModel(title: "Compressed", value: MonitorFormatting.bytes(memory.compressedBytes), color: .yellow)
            ]
        case .energy:
            let energy = snapshot.summary.energy
            return [
                MetricCardModel(title: "Avg Impact", value: String(format: "%.2f", energy.averageImpact), color: .yellow),
                MetricCardModel(title: "Power", value: energy.powerSource, color: .green),
                MetricCardModel(title: "Battery", value: energy.batteryPercent.map { MonitorFormatting.percent($0) } ?? "N/A", color: .secondary),
                MetricCardModel(title: "Preventing Sleep", value: "\(energy.preventingSleepCount)", color: .orange),
                MetricCardModel(title: "Processes", value: "\(snapshot.processes.count)", color: .secondary)
            ]
        case .disk:
            return [
                MetricCardModel(title: "Reads/s", value: MonitorFormatting.countRate(history.diskReadsPerSecond.last ?? 0), color: .blue),
                MetricCardModel(title: "Writes/s", value: MonitorFormatting.countRate(history.diskWritesPerSecond.last ?? 0), color: .purple),
                MetricCardModel(title: "Read/s", value: MonitorFormatting.rate(history.diskReadBytesPerSecond.last ?? 0), color: .blue),
                MetricCardModel(title: "Written/s", value: MonitorFormatting.rate(history.diskWrittenBytesPerSecond.last ?? 0), color: .purple)
            ]
        case .network:
            return [
                MetricCardModel(title: "Packets In/s", value: MonitorFormatting.countRate(history.networkPacketsInPerSecond.last ?? 0), color: .blue),
                MetricCardModel(title: "Packets Out/s", value: MonitorFormatting.countRate(history.networkPacketsOutPerSecond.last ?? 0), color: .green),
                MetricCardModel(title: "Data In/s", value: MonitorFormatting.rate(history.networkBytesInPerSecond.last ?? 0), color: .blue),
                MetricCardModel(title: "Data Out/s", value: MonitorFormatting.rate(history.networkBytesOutPerSecond.last ?? 0), color: .green)
            ]
        case .cache:
            let cache = snapshot.summary.cache
            return [
                MetricCardModel(title: "Available", value: cache.isAvailable ? "Yes" : "No", color: cache.isAvailable ? .green : .secondary),
                MetricCardModel(title: "Active", value: cache.isActive ? "Yes" : "No", color: cache.isActive ? .green : .secondary),
                MetricCardModel(title: "Served", value: MonitorFormatting.bytes(cache.servedBytes), color: .blue),
                MetricCardModel(title: "Dropped", value: MonitorFormatting.bytes(cache.droppedBytes), color: .red),
                MetricCardModel(title: "Origin", value: MonitorFormatting.bytes(cache.originBytes), color: .purple)
            ]
        }
    }

    private var tint: Color {
        switch selectedPane {
        case .cpu: .blue
        case .memory: .green
        case .energy: .yellow
        case .disk: .purple
        case .network: .cyan
        case .cache: .orange
        }
    }

    private var graphValues: [Double] {
        let values = history.values(for: selectedPane)
        return values.isEmpty ? [0, 0, 0] : values
    }
}

private func memoryPressureColor(_ pressure: Double) -> Color {
    switch pressure {
    case 0.7...:
        .red
    case 0.4..<0.7:
        .orange
    default:
        .green
    }
}

private func memoryPressureLabel(_ pressure: Double) -> String {
    switch pressure {
    case 0.7...:
        "High"
    case 0.4..<0.7:
        "Medium"
    default:
        "Low"
    }
}

private struct MetricCardModel: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let color: Color
}

private struct MetricCard: View {
    let card: MetricCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(card.value)
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundStyle(card.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 116, alignment: .leading)
    }
}

private struct MiniGraph: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(values.max() ?? 1, 1)
            Path { path in
                let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
                for index in values.indices {
                    let x = CGFloat(index) * step
                    let y = proxy.size.height - CGFloat(values[index] / maxValue) * proxy.size.height
                    if index == values.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: .rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
        }
    }
}

private struct ProcessTable: View {
    @Bindable var store: MonitorStore

    var body: some View {
        AppKitProcessTableView(
            processes: store.displayedProcesses,
            columns: store.settings.visibleColumns(for: store.selectedPane),
            columnWidths: Dictionary(uniqueKeysWithValues: store.settings.visibleColumns(for: store.selectedPane).map {
                ($0, CGFloat(store.settings.width(for: $0, pane: store.selectedPane)))
            }),
            selectedPane: store.selectedPane,
            sortKey: store.sortKey,
            sortAscending: store.sortAscending,
            selectedProcessID: $store.selectedProcessID,
            onSort: store.setSort,
            onColumnsChanged: { columns in
                store.settings.setColumns(columns, pane: store.selectedPane)
            },
            onColumnWidthChanged: { column, width in
                store.settings.setWidth(Double(width), for: column, pane: store.selectedPane)
            },
            onProcessAction: { action, process in
                store.selectedProcessID = process.pid
                Task { await store.requestSelectedAction(action) }
            }
        )
    }
}

private struct ProcessTableHeader: View {
    @Bindable var store: MonitorStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(store.settings.visibleColumns(for: store.selectedPane)) { column in
                if let key = column.sortKey {
                    HeaderButton(title: column.label, key: key, width: column.width, store: store)
                } else {
                    Text(column.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: column.width, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct HeaderButton: View {
    let title: String
    let key: ProcessSortKey
    let width: CGFloat
    @Bindable var store: MonitorStore

    var body: some View {
        Button {
            store.setSort(key)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                if store.sortKey == key {
                    Image(systemName: store.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct ProcessRow: View {
    let process: ProcessSnapshot
    let selectedPane: MonitorPane
    let isSelected: Bool
    @Environment(MonitorSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(settings.visibleColumns(for: selectedPane)) { column in
                rowValue(for: column)
                    .frame(width: column.width, alignment: .leading)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private var icon: String {
        switch selectedPane {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .energy: "bolt"
        case .disk: "internaldrive"
        case .network: "network"
        case .cache: "shippingbox"
        }
    }

    @ViewBuilder
    private func rowValue(for column: ProcessColumn) -> some View {
        switch column {
        case .name:
            Label(String(repeating: "  ", count: process.hierarchyLevel) + process.name, systemImage: icon)
                .lineLimit(1)
        case .pid:
            Text("\(process.pid)")
        case .user:
            Text(process.user)
                .lineLimit(1)
        case .cpu:
            Text(MonitorFormatting.percent(process.cpuPercent))
                .monospacedDigit()
        case .memory:
            Text(MonitorFormatting.bytes(process.residentMemoryBytes))
                .monospacedDigit()
        case .energy:
            Text(String(format: "%.1f", process.energyImpact))
                .monospacedDigit()
        case .disk:
            Text(MonitorFormatting.bytes(process.diskReadBytes + process.diskWriteBytes))
                .monospacedDigit()
        case .diskRead:
            Text(MonitorFormatting.bytes(process.diskReadBytes))
                .monospacedDigit()
        case .diskWritten:
            Text(MonitorFormatting.bytes(process.diskWriteBytes))
                .monospacedDigit()
        case .network:
            Text(MonitorFormatting.bytes(process.networkReceivedBytes + process.networkSentBytes))
                .monospacedDigit()
        case .networkReceived:
            Text(MonitorFormatting.bytes(process.networkReceivedBytes))
                .monospacedDigit()
        case .networkSent:
            Text(MonitorFormatting.bytes(process.networkSentBytes))
                .monospacedDigit()
        case .state:
            Text(process.state)
        case .threads:
            Text("\(process.threadCount)")
                .monospacedDigit()
        case .ports:
            Text(process.portsCount.map(String.init) ?? "—")
                .monospacedDigit()
        case .preventingSleep:
            Text(process.preventsSleep.map { $0 ? "Yes" : "No" } ?? "—")
        case .wakeups:
            Text(process.wakeups.map(String.init) ?? "—")
                .monospacedDigit()
        case .cpuTime:
            Text(process.cpuTime)
                .monospacedDigit()
        }
    }
}

private struct StatusBar: View {
    @Bindable var store: MonitorStore

    var body: some View {
        HStack(spacing: 12) {
            Text("\(store.displayedProcesses.count) of \(store.snapshot.processes.count) processes")
            if store.isShowingSearchFallback {
                Text("No search matches; showing all")
                    .foregroundStyle(.orange)
            }
            Text(store.snapshot.capturedAt == .distantPast ? "Not sampled yet" : "Last update \(MonitorFormatting.shortDate(store.snapshot.capturedAt))")
            Text("Refresh \(String(format: "%.0f", store.lastRefreshDuration * 1_000)) ms")
            if store.lastActionMessage != "Ready" {
                Text(store.lastActionMessage)
                    .lineLimit(1)
            }
            Spacer()
            Text(store.settings.showPrivateAPINotice ? "Private parity mode enabled" : "Public API mode")
                .foregroundStyle(store.settings.showPrivateAPINotice ? .orange : .secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
    }
}

struct SettingsView: View {
    @Bindable var settings: MonitorSettings
    @State private var selectedPane: MonitorPane = .cpu

    var body: some View {
        Form {
            Picker("Update Frequency", selection: $settings.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }

            Picker("Dock Icon", selection: $settings.dockIconMode) {
                ForEach(DockIconMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Toggle("Show private API parity notice", isOn: $settings.showPrivateAPINotice)
            Toggle("Launch showing all processes", isOn: $settings.launchWithAllProcesses)

            Section("Columns") {
                Picker("Pane", selection: $selectedPane) {
                    ForEach(MonitorPane.allCases) { pane in
                        Text(pane.title).tag(pane)
                    }
                }

                ForEach(ProcessColumn.allCases) { column in
                    Toggle(column.label, isOn: Binding(
                        get: { settings.isColumnVisible(column, pane: selectedPane) },
                        set: { settings.setColumn(column, isVisible: $0, pane: selectedPane) }
                    ))
                    .disabled(column == .name)
                }

                Button("Reset Columns for \(selectedPane.title)") {
                    settings.resetColumns(for: selectedPane)
                }
            }
        }
        .padding(20)
        .frame(width: 420, height: 520)
    }
}
