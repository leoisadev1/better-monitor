import SwiftUI
import AppKit

@main
struct BetterMonitorApp: App {
    @NSApplicationDelegateAdaptor(BetterMonitorApplicationDelegate.self) private var applicationDelegate
    @State private var store = MonitorStore()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1280, minHeight: 780)
                .environment(store.settings)
                .task {
                    await store.start()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updater.checkForUpdates()
                }
            }
            MonitorCommands(store: store)
        }

        Window("CPU History", id: "cpu-history") {
            HistoryWindowView(title: "CPU History", mode: .cpu, store: store)
                .frame(width: 520, height: 260)
        }

        Window("GPU History", id: "gpu-history") {
            HistoryWindowView(title: "GPU History", mode: .gpu, store: store)
                .frame(width: 520, height: 260)
        }

        Settings {
            SettingsView(settings: store.settings)
        }
    }
}

final class BetterMonitorApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MonitorCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let store: MonitorStore

    var body: some Commands {
        CommandMenu("Monitor") {
            Button("Refresh Now") {
                Task { await store.refreshNow() }
            }
            .keyboardShortcut("r", modifiers: [.command])

            Menu("Update Frequency") {
                ForEach(RefreshInterval.allCases) { interval in
                    Button(interval.label) {
                        store.settings.refreshInterval = interval
                    }
                    .disabled(store.settings.refreshInterval == interval)
                }
            }

            Menu("Dock Icon") {
                ForEach(DockIconMode.allCases) { mode in
                    Button(mode.label) {
                        store.settings.dockIconMode = mode
                        store.updateDockIcon()
                    }
                    .disabled(store.settings.dockIconMode == mode)
                }
            }

            Menu("Pane") {
                ForEach(MonitorPane.allCases) { pane in
                    Button(pane.title) {
                        store.selectedPane = pane
                    }
                    .keyboardShortcut(KeyEquivalent(pane.keyboardEquivalent), modifiers: [.command])
                    .disabled(store.selectedPane == pane)
                }
            }

            Menu("Process Scope") {
                ForEach(ProcessScope.allCases) { scope in
                    Button(scope.label) {
                        store.selectedScope = scope
                    }
                    .disabled(store.selectedScope == scope)
                }
            }

            Divider()

            Button("Quit Process") {
                Task { await store.requestSelectedAction(.quit) }
            }
            .disabled(store.selectedProcessID == nil)

            Button("Force Quit Process") {
                Task { await store.requestSelectedAction(.forceQuit) }
            }
            .disabled(store.selectedProcessID == nil)
        }

        CommandMenu("Monitor Windows") {
            Button("CPU History") {
                openWindow(id: "cpu-history")
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Button("GPU History") {
                openWindow(id: "gpu-history")
            }
            .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Menu("Columns") {
                ForEach(ProcessColumn.allCases) { column in
                    Toggle(column.label, isOn: Binding(
                        get: { store.settings.isColumnVisible(column, pane: store.selectedPane) },
                        set: { store.settings.setColumn(column, isVisible: $0, pane: store.selectedPane) }
                    ))
                    .disabled(column == .name)
                }

                Divider()

                Button("Reset Columns for \(store.selectedPane.title)") {
                    store.settings.resetColumns(for: store.selectedPane)
                }
            }
        }
    }
}
