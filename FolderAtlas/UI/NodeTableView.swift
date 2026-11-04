import SwiftUI
import AppKit

/// Native NSOutlineView driving BOTH layouts (flat list = single level,
/// tree = expandable). Replaces SwiftUI `Table`, whose AppKit coordinator
/// prepared an NSHostingView for every row affected by a data change —
/// on million-row maps one sort click prepared the whole index set and hung
/// the app for minutes (sampled: AppKitOutlineTableCoordinator → endUpdates
/// → _preparedRowViewForRow). NSTableView is lazy: reloadData touches only
/// visible rows.
struct NodeTableRepresentable: NSViewRepresentable {
    let session: MapSession
    let tree: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(tree: tree)
    }

    func makeNSView(context: Context) -> NSOutlineView {
        context.coordinator.makeView(session: session)
    }

    func updateNSView(_ nsView: NSOutlineView, context: Context) {
        context.coordinator.sync(session: session)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

        final class ItemBox {
            let row: NodeRow
            init(_ row: NodeRow) { self.row = row }
        }

        private final class ActionBox: NSObject {
            let handler: () -> Void
            init(_ handler: @escaping () -> Void) {
                self.handler = handler
                super.init()
            }
            @objc func run() { handler() }
        }

        private let tree: Bool
        private var session: MapSession?
        private var table: NSOutlineView?

        private static let emptyBox = ItemBox(NodeRow(NodeRecord(
            id: -1, parentID: nil, name: "", relativePath: "", ext: nil,
            isDirectory: false, isHidden: false, isSymlink: false, isPackage: false,
            size: nil, allocSize: nil, created: nil, modified: nil, tags: nil,
            notDownloaded: false)))

        private var appliedRevision = -1
        private var appliedTree = false
        private var appliedLayout: MapSession.ColumnLayout?
        private var suppressSelectionSync = false
        private var menuActions: [ActionBox] = []
        private var expandedIDs: Set<Int64> = []
        private var boxCache: [Int64: ItemBox] = [:]
        private var notificationObservers: [NSObjectProtocol] = []

        /// Top-level boxes for the current tree snapshot (tree mode only).
        private var topBoxes: [ItemBox] = []

        init(tree: Bool) {
            self.tree = tree
            super.init()
        }

        deinit {
            // Block observers hold [weak self] and target the table object;
            // NotificationCenter drops the registrations when the table is
            // deallocated, so no manual cleanup is needed (and deinit must
            // not touch MainActor-isolated state under Swift 6).
        }

        // MARK: View construction

        func makeView(session: MapSession) -> NSOutlineView {
            let table = NSOutlineView()
            table.headerView = NSTableHeaderView()
            table.allowsColumnReordering = true
            table.allowsColumnResizing = true
            table.allowsMultipleSelection = true
            table.allowsEmptySelection = true
            table.usesAlternatingRowBackgroundColors = true
            table.rowHeight = 24
            table.rowSizeStyle = .custom
            table.usesAutomaticRowHeights = false
            table.indentationPerLevel = 14
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.doubleAction = #selector(doubleClicked(_:))
            self.table = table
            self.session = session
            rebuildColumns(session: session)

            let center = NotificationCenter.default
            notificationObservers.append(center.addObserver(
                forName: NSTableView.columnDidMoveNotification, object: table, queue: .main) { [weak self] _ in
                self?.persistColumnLayout()
            })
            notificationObservers.append(center.addObserver(
                forName: NSTableView.columnDidResizeNotification, object: table, queue: .main) { [weak self] _ in
                self?.persistColumnLayout()
            })
            return table
        }

        private func rebuildColumns(session: MapSession) {
            guard let table else { return }
            table.tableColumns.forEach(table.removeTableColumn)
            for column in session.columnLayout.visible {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
                tableColumn.title = column.title
                tableColumn.width = CGFloat(session.columnLayout.widths[column.rawValue]
                                            ?? Self.defaultWidths[column] ?? 120)
                tableColumn.minWidth = 40
                tableColumn.maxWidth = 900
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(
                    key: column.rawValue, ascending: true)
                table.addTableColumn(tableColumn)
            }
            table.outlineTableColumn = table.tableColumns.first
            appliedLayout = session.columnLayout
        }

        private static let defaultWidths: [NodeColumn: CGFloat] = [
            .name: 260, .kind: 90, .ext: 70, .size: 100, .sizeOnDisk: 100,
            .created: 150, .modified: 150, .tags: 140, .path: 280,
            .items: 70, .nestedItems: 80, .folderSize: 100, .sha256: 260,
            .dimensions: 100, .duration: 80, .codec: 90, .flags: 110
        ]

        // MARK: Sync

        func sync(session: MapSession) {
            self.session = session
            guard let table else { return }

            if appliedRevision != session.displayRevision || appliedTree != tree {
                appliedRevision = session.displayRevision
                appliedTree = tree
                if appliedLayout != session.columnLayout {
                    rebuildColumns(session: session)
                }
                reloadPreservingState()
            } else if appliedLayout != session.columnLayout {
                rebuildColumns(session: session)
                table.reloadData()
            }

            table.sortDescriptors = session.sortOrder.map {
                NSSortDescriptor(key: $0.column.rawValue, ascending: $0.order == .forward)
            }

            let selectedIDs = currentSelectedIDs()
            if !suppressSelectionSync && selectedIDs != session.selection {
                applySelection(session.selection)
            }
        }

        private func currentSelectedIDs() -> Set<Int64> {
            guard let table else { return [] }
            var ids = Set<Int64>()
            table.selectedRowIndexes.forEach { row in
                if let box = table.item(atRow: row) as? ItemBox {
                    ids.insert(box.row.id)
                }
            }
            return ids
        }

        private func reloadPreservingState() {
            guard let table, let session else { return }
            let previousIDs = currentSelectedIDs()

            if tree {
                topBoxes = (session.treeRows ?? []).map { box(for: $0) }
                table.reloadData()
                // Re-expand saved folders (their row items must exist first).
                for box in topBoxes {
                    restoreExpansion(of: box)
                }
            } else {
                table.reloadData()
                if !previousIDs.isEmpty {
                    var indexByID: [Int64: Int] = [:]
                    indexByID.reserveCapacity(session.visibleRows.count)
                    for (index, row) in session.visibleRows.enumerated() {
                        indexByID[row.id] = index
                    }
                    var indexes = IndexSet()
                    for id in previousIDs {
                        if let index = indexByID[id] { indexes.insert(index) }
                    }
                    suppressSelectionSync = true
                    table.selectRowIndexes(indexes, byExtendingSelection: false)
                    suppressSelectionSync = false
                }
            }
        }

        private func restoreExpansion(of itemBox: ItemBox) {
            guard let table else { return }
            let row = itemBox.row
            if expandedIDs.isEmpty {
                // First load: expand the root only.
                if row.record.hasChildren {
                    expandedIDs.insert(row.id)
                    table.expandItem(itemBox, expandChildren: false)
                }
                return
            }
            if row.record.hasChildren, expandedIDs.contains(row.id) {
                table.expandItem(itemBox, expandChildren: false)
            }
            if let children = row.children, expandedIDs.contains(row.id) {
                for child in children {
                    restoreExpansion(of: box(for: child))
                }
            }
        }

        private func box(for row: NodeRow) -> ItemBox {
            if let cached = boxCache[row.id] { return cached }
            let newBox = ItemBox(row)
            boxCache[row.id] = newBox
            return newBox
        }

        private func applySelection(_ ids: Set<Int64>) {
            guard let table, let session else { return }
            var indexes = IndexSet()
            if tree {
                func find(in rows: [NodeRow]) {
                    for row in rows {
                        if ids.contains(row.id), let box = boxIfCached(row.id) {
                            let rowIndex = table.row(forItem: box)
                            if rowIndex >= 0 { indexes.insert(rowIndex) }
                        }
                        if let children = row.children, expandedIDs.contains(row.id) {
                            find(in: children)
                        }
                    }
                }
                find(in: session.treeRows ?? [])
            } else {
                var indexByID: [Int64: Int] = [:]
                for (index, row) in session.visibleRows.enumerated() {
                    indexByID[row.id] = index
                }
                for id in ids {
                    if let index = indexByID[id] { indexes.insert(index) }
                }
            }
            suppressSelectionSync = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            suppressSelectionSync = false
        }

        private func boxIfCached(_ id: Int64) -> ItemBox? {
            boxCache[id]
        }

        private func persistColumnLayout() {
            guard let table, let session else { return }
            var visible: [NodeColumn] = []
            var widths: [String: Double] = session.columnLayout.widths
            for tableColumn in table.tableColumns {
                if let column = NodeColumn(rawValue: tableColumn.identifier.rawValue) {
                    visible.append(column)
                    widths[column.rawValue] = Double(tableColumn.width)
                }
            }
            let layout = MapSession.ColumnLayout(visible: visible, widths: widths)
            appliedLayout = layout
            if layout != session.columnLayout {
                session.columnLayout = layout
            }
        }

        // MARK: Actions

        @objc private func doubleClicked(_ sender: Any?) {
            guard let session, let table, !suppressSelectionSync else { return }
            let ids = currentSelectedIDs()
            if let id = ids.first, let node = session.snapshot?.node(id) {
                session.open(node)
            }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let session else { return 0 }
            if let box = item as? ItemBox {
                return tree ? (box.row.children?.count ?? 0) : 0
            }
            return tree ? (session.treeRows?.count ?? 0) : session.visibleRows.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let session else { return Self.emptyBox }
            if let itemBox = item as? ItemBox, let children = itemBox.row.children {
                return box(for: children[index])
            }
            return box(for: tree ? session.treeRows![index] : session.visibleRows[index])
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let box = item as? ItemBox else { return false }
            return tree && box.row.record.hasChildren && !(box.row.children?.isEmpty ?? true)
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let box = item as? ItemBox,
                  let rawID = tableColumn?.identifier.rawValue,
                  let column = NodeColumn(rawValue: rawID) else { return nil }
            return CellFactory.view(for: box.row, column: column)
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            24
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !suppressSelectionSync, let session, let table = notification.object as? NSOutlineView else { return }
            var ids = Set<Int64>()
            table.selectedRowIndexes.forEach { row in
                if let box = table.item(atRow: row) as? ItemBox {
                    ids.insert(box.row.id)
                }
            }
            session.selection = ids
        }

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let box = notification.userInfo?["NSObject"] as? ItemBox else { return }
            expandedIDs.insert(box.row.id)
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard let box = notification.userInfo?["NSObject"] as? ItemBox else { return }
            expandedIDs.remove(box.row.id)
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let session else { return }
            let sorts: [ColumnSort] = tableView.sortDescriptors.compactMap { descriptor in
                guard let key = descriptor.key, let column = NodeColumn(rawValue: key) else { return nil }
                return ColumnSort(column: column, order: descriptor.ascending ? .forward : .reverse)
            }
            if !sorts.isEmpty {
                session.sortOrder = sorts
            }
        }

        func tableView(_ tableView: NSTableView, menuForEvent event: NSEvent, row: Int, column: Int) -> NSMenu? {
            guard let session, let table else { return nil }
            guard let clickedBox = table.item(atRow: row) as? ItemBox else { return nil }
            var ids = currentSelectedIDs()
            if !ids.contains(clickedBox.row.id) {
                ids = [clickedBox.row.id]
            }
            return buildMenu(ids: ids)
        }

        private func buildMenu(ids: Set<Int64>) -> NSMenu {
            guard let session else { return NSMenu() }
            let menu = NSMenu()
            menuActions.removeAll(keepingCapacity: false)

            func add(_ key: String, _ handler: @escaping () -> Void) {
                let action = ActionBox(handler)
                menuActions.append(action)
                let item = NSMenuItem(title: String(localized: String.LocalizationValue(key)),
                                      action: #selector(ActionBox.run), keyEquivalent: "")
                item.target = action
                menu.addItem(item)
            }

            let nodes = ids.compactMap { session.snapshot?.node($0) }
            if nodes.count == 1, let node = nodes.first {
                add("Open") { session.open(node) }
                add("Show in Finder") { session.reveal(node) }
                add("Quick Look") {
                    session.selection = ids
                    session.quickLookSelection()
                }
                menu.addItem(.separator())
                add("Copy Path") { session.copyPath(node) }
                add("Copy Name") { NSPasteboardHelper.copy(node.name) }
                menu.addItem(.separator())
                add("Compute SHA-256") { session.computeChecksums(scope: .selection) }
                add("Extract media & EXIF") { session.extractMediaMetadata(scope: .selection) }
            } else if nodes.count > 1 {
                add("Copy Paths") { session.copyPaths(session.selectedNodes) }
                add("Quick Look") {
                    session.selection = ids
                    session.quickLookSelection()
                }
                menu.addItem(.separator())
                add("Compute SHA-256") { session.computeChecksums(scope: .selection) }
                add("Extract media & EXIF") { session.extractMediaMetadata(scope: .selection) }
            } else {
                add("Copy Paths") { session.copyPaths(session.selectedNodes) }
            }
            return menu
        }
    }
}

// MARK: - Cell factory (pure AppKit — no SwiftUI hosting views in rows)

@MainActor
enum CellFactory {

    static func view(for row: NodeRow, column: NodeColumn) -> NSView {
        let node = row.record
        switch column {
        case .name:
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: NodeIcons.symbol(for: node),
                                 accessibilityDescription: NodeFormatters.kindName(node.kind))
            icon.contentTintColor = .secondaryLabelColor
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            let text = NSTextField(labelWithString: node.displayName)
            text.font = .systemFont(ofSize: 13, weight: node.isDirectory ? .semibold : .regular)
            text.lineBreakMode = .byTruncatingTail
            return horizontalCell([icon, text])

        case .flags:
            var views: [NSView] = []
            func flag(_ symbol: String, _ help: String, _ color: NSColor = .secondaryLabelColor) {
                let imageView = NSImageView()
                imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
                imageView.contentTintColor = color
                imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
                imageView.toolTip = help
                views.append(imageView)
            }
            if node.isHidden { flag("eye.slash", "Hidden") }
            if node.isSymlink { flag("arrow.triangle.branch", "Symlink") }
            if node.notDownloaded { flag("icloud.slash", "Not downloaded from iCloud") }
            if node.isPackage { flag("shippingbox", "Package") }
            if node.error != nil { flag("exclamationmark.triangle", "Scan error", .systemOrange) }
            return horizontalCell(views.isEmpty
                ? [label(Fmt.unknown, secondary: true, mono: false)]
                : views)

        default:
            let value: String
            let secondary: Bool
            let mono: Bool
            let head: Bool
            switch column {
            case .kind:
                value = NodeFormatters.kindName(node.kind); secondary = true; mono = false; head = false
            case .ext:
                value = node.ext ?? Fmt.unknown; secondary = true; mono = false; head = false
            case .size:
                value = Fmt.size(node.size); secondary = false; mono = true; head = false
            case .sizeOnDisk:
                value = Fmt.size(node.allocSize); secondary = true; mono = true; head = false
            case .created:
                value = Fmt.date(node.created); secondary = true; mono = false; head = false
            case .modified:
                value = Fmt.date(node.modified); secondary = true; mono = false; head = false
            case .tags:
                let hasTags = node.tags != nil && !node.tags!.isEmpty
                value = hasTags ? node.tags!.joined(separator: ", ") : Fmt.unknown
                secondary = !hasTags; mono = false; head = false
            case .path:
                value = node.relativePath; secondary = true; mono = false; head = true
            case .items:
                value = Fmt.count(node.childCount); secondary = false; mono = true; head = false
            case .nestedItems:
                value = Fmt.count(node.descendantCount); secondary = false; mono = true; head = false
            case .folderSize:
                value = Fmt.size(node.dirSize); secondary = false; mono = true; head = false
            case .sha256:
                value = node.sha256 ?? Fmt.unknown; secondary = false; mono = false; head = false
            case .dimensions:
                value = Fmt.dimensions(node.imageInfo?.pixelWidth, node.imageInfo?.pixelHeight)
                secondary = false; mono = false; head = false
            case .duration:
                value = Fmt.seconds(node.mediaInfo?.durationSeconds); secondary = false; mono = false; head = false
            case .codec:
                value = node.mediaInfo?.codec ?? Fmt.unknown; secondary = false; mono = false; head = false
            default:
                value = ""; secondary = false; mono = false; head = false
            }
            let field = label(value, secondary: secondary, mono: mono)
            field.lineBreakMode = head ? .byTruncatingHead : .byTruncatingTail
            if column == .sha256 {
                field.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            }
            if column == .path, !node.relativePath.isEmpty {
                field.toolTip = node.relativePath
            }
            return wrap(field)
        }
    }

    private static func label(_ string: String, secondary: Bool, mono: Bool) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = mono
            ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private static func wrap(_ field: NSTextField) -> NSView {
        let cell = NSTableCellView()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private static func horizontalCell(_ views: [NSView]) -> NSView {
        let cell = NSTableCellView()
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        if let text = views.compactMap({ $0 as? NSTextField }).first {
            text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        return cell
    }
}
