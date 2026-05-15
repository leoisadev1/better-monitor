import AppKit
import SwiftUI

struct AppKitProcessTableView: NSViewRepresentable {
    let processes: [ProcessSnapshot]
    let columns: [ProcessColumn]
    let columnWidths: [ProcessColumn: CGFloat]
    let selectedPane: MonitorPane
    let sortKey: ProcessSortKey
    let sortAscending: Bool
    @Binding var selectedProcessID: Int32?
    let onSort: (ProcessSortKey) -> Void
    let onColumnsChanged: ([ProcessColumn]) -> Void
    let onColumnWidthChanged: (ProcessColumn, CGFloat) -> Void
    let onProcessAction: (ProcessAction, ProcessSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedProcessID: $selectedProcessID,
            onSort: onSort,
            onColumnsChanged: onColumnsChanged,
            onColumnWidthChanged: onColumnWidthChanged,
            onProcessAction: onProcessAction
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = ProcessNSTableView()
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.contextMenuProvider = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.headerView = NSTableHeaderView()
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.style = .plain
        tableView.doubleAction = #selector(Coordinator.doubleClickSelectedRow(_:))
        tableView.target = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        context.coordinator.tableView = tableView
        context.coordinator.sync(processes: processes, columns: columns, columnWidths: columnWidths, selectedPane: selectedPane, sortKey: sortKey, sortAscending: sortAscending)
        context.coordinator.rebuildColumns()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.tableView = tableView
        context.coordinator.selectedProcessID = $selectedProcessID
        context.coordinator.onSort = onSort
        context.coordinator.onColumnsChanged = onColumnsChanged
        context.coordinator.onColumnWidthChanged = onColumnWidthChanged
        context.coordinator.onProcessAction = onProcessAction
        let columnsChanged = context.coordinator.columns != columns
        let widthsChanged = context.coordinator.columnWidths != columnWidths
        context.coordinator.sync(processes: processes, columns: columns, columnWidths: columnWidths, selectedPane: selectedPane, sortKey: sortKey, sortAscending: sortAscending)
        if columnsChanged {
            context.coordinator.rebuildColumns()
        } else {
            if widthsChanged {
                context.coordinator.applyColumnWidths()
            }
            context.coordinator.updateSortDescriptors()
        }
        tableView.reloadData()
        context.coordinator.syncSelectionFromBinding()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, ProcessTableContextMenuProvider {
        var processes: [ProcessSnapshot] = []
        var columns: [ProcessColumn] = []
        var columnWidths: [ProcessColumn: CGFloat] = [:]
        var selectedPane: MonitorPane = .cpu
        var sortKey: ProcessSortKey = .cpu
        var sortAscending = false
        var selectedProcessID: Binding<Int32?>
        var onSort: (ProcessSortKey) -> Void
        var onColumnsChanged: ([ProcessColumn]) -> Void
        var onColumnWidthChanged: (ProcessColumn, CGFloat) -> Void
        var onProcessAction: (ProcessAction, ProcessSnapshot) -> Void
        weak var tableView: NSTableView?
        private var isSyncingSelection = false
        private var isRebuildingColumns = false

        init(
            selectedProcessID: Binding<Int32?>,
            onSort: @escaping (ProcessSortKey) -> Void,
            onColumnsChanged: @escaping ([ProcessColumn]) -> Void,
            onColumnWidthChanged: @escaping (ProcessColumn, CGFloat) -> Void,
            onProcessAction: @escaping (ProcessAction, ProcessSnapshot) -> Void
        ) {
            self.selectedProcessID = selectedProcessID
            self.onSort = onSort
            self.onColumnsChanged = onColumnsChanged
            self.onColumnWidthChanged = onColumnWidthChanged
            self.onProcessAction = onProcessAction
        }

        func sync(processes: [ProcessSnapshot], columns: [ProcessColumn], columnWidths: [ProcessColumn: CGFloat], selectedPane: MonitorPane, sortKey: ProcessSortKey, sortAscending: Bool) {
            self.processes = processes
            self.columns = columns
            self.columnWidths = columnWidths
            self.selectedPane = selectedPane
            self.sortKey = sortKey
            self.sortAscending = sortAscending
        }

        func rebuildColumns() {
            guard let tableView else { return }
            isRebuildingColumns = true
            defer { isRebuildingColumns = false }
            for tableColumn in tableView.tableColumns {
                tableView.removeTableColumn(tableColumn)
            }

            for column in columns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
                tableColumn.title = column.label
                tableColumn.width = columnWidths[column] ?? column.width
                tableColumn.minWidth = min(56, column.width)
                tableColumn.resizingMask = [.userResizingMask]
                if column.sortKey != nil {
                    tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
                }
                tableView.addTableColumn(tableColumn)
            }
            updateSortDescriptors()
        }

        func applyColumnWidths() {
            guard let tableView else { return }
            isRebuildingColumns = true
            defer { isRebuildingColumns = false }
            for tableColumn in tableView.tableColumns {
                guard let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue),
                      let width = columnWidths[column]
                else {
                    continue
                }
                tableColumn.width = width
            }
        }

        func updateSortDescriptors() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                tableView.setIndicatorImage(nil, in: column)
                guard column.identifier.rawValue == processColumn(for: sortKey)?.rawValue else { continue }
                let imageName = sortAscending ? NSImage.touchBarGoUpTemplateName : NSImage.touchBarGoDownTemplateName
                tableView.setIndicatorImage(NSImage(named: imageName), in: column)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            processes.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < processes.count,
                  let identifier = tableColumn?.identifier,
                  let column = ProcessColumn(rawValue: identifier.rawValue)
            else {
                return nil
            }

            let cellIdentifier = NSUserInterfaceItemIdentifier("ProcessCell-\(column.rawValue)")
            let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView ?? makeCell(identifier: cellIdentifier, column: column)
            cell.textField?.stringValue = ProcessColumnValue.string(for: column, process: processes[row])
            cell.textField?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            if column == .name {
                cell.textField?.font = .systemFont(ofSize: 12)
                cell.imageView?.image = ProcessIconProvider.icon(for: processes[row])
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                  let tableView,
                  tableView.selectedRow >= 0,
                  tableView.selectedRow < processes.count
            else {
                return
            }
            selectedProcessID.wrappedValue = processes[tableView.selectedRow].pid
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue),
                  let sortKey = column.sortKey
            else {
                return
            }
            onSort(sortKey)
        }

        func tableViewColumnDidMove(_ notification: Notification) {
            guard !isRebuildingColumns, let tableView else { return }
            let reordered = tableView.tableColumns.compactMap { ProcessColumn(rawValue: $0.identifier.rawValue) }
            guard !reordered.isEmpty, reordered != columns else { return }
            onColumnsChanged(reordered)
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard !isRebuildingColumns,
                  let tableColumn = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  let column = ProcessColumn(rawValue: tableColumn.identifier.rawValue)
            else {
                return
            }
            onColumnWidthChanged(column, tableColumn.width)
        }

        @objc func doubleClickSelectedRow(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, sender.clickedRow < processes.count else { return }
            selectedProcessID.wrappedValue = processes[sender.clickedRow].pid
        }

        func menu(for row: Int) -> NSMenu? {
            guard row >= 0, row < processes.count, let tableView else { return nil }
            let process = processes[row]
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            selectedProcessID.wrappedValue = process.pid

            let menu = NSMenu()
            menu.addItem(menuItem(title: "Quit \(process.name)", action: .quit, process: process))
            menu.addItem(menuItem(title: "Force Quit \(process.name)", action: .forceQuit, process: process))
            return menu
        }

        @objc private func runContextMenuAction(_ sender: NSMenuItem) {
            guard let context = sender.representedObject as? ProcessContextMenuAction else { return }
            selectedProcessID.wrappedValue = context.process.pid
            onProcessAction(context.action, context.process)
        }

        func syncSelectionFromBinding() {
            guard let tableView else { return }
            guard let selected = selectedProcessID.wrappedValue,
                  let index = processes.firstIndex(where: { $0.pid == selected })
            else {
                isSyncingSelection = true
                tableView.deselectAll(nil)
                isSyncingSelection = false
                return
            }
            guard tableView.selectedRow != index else { return }
            isSyncingSelection = true
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            isSyncingSelection = false
        }

        private func makeCell(identifier: NSUserInterfaceItemIdentifier, column: ProcessColumn) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = textField
            cell.addSubview(textField)

            if column == .name {
                let imageView = NSImageView()
                imageView.imageScaling = .scaleProportionallyDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = imageView
                cell.addSubview(imageView)

                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 18),
                    imageView.heightAnchor.constraint(equalToConstant: 18),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }

            return cell
        }

        private func processColumn(for sortKey: ProcessSortKey) -> ProcessColumn? {
            ProcessColumn.allCases.first { $0.sortKey == sortKey }
        }

        private func menuItem(title: String, action: ProcessAction, process: ProcessSnapshot) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(runContextMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ProcessContextMenuAction(action: action, process: process)
            return item
        }
    }
}

@MainActor
private protocol ProcessTableContextMenuProvider: AnyObject {
    func menu(for row: Int) -> NSMenu?
}

@MainActor
private final class ProcessNSTableView: NSTableView {
    weak var contextMenuProvider: ProcessTableContextMenuProvider?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?.menu(for: row(at: point))
    }
}

private final class ProcessContextMenuAction {
    let action: ProcessAction
    let process: ProcessSnapshot

    init(action: ProcessAction, process: ProcessSnapshot) {
        self.action = action
        self.process = process
    }
}
