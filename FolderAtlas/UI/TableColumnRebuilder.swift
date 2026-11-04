import AppKit

/// Rebuilds the column set of an NSOutlineView to match a target layout.
///
/// The outline column is special: NSOutlineView REFUSES to remove it via
/// `removeTableColumn:` ("cannot remove outlineTableColumn — use
/// setOutlineTableColumn: instead"). Blindly removing everything and
/// re-adding therefore left the old outline column in place and added a
/// second copy on top — the "duplicated Имя" bug. The strategy here:
/// repoint the outline column to a surviving column, remove the rest,
/// add what is missing, then reorder with moveColumn.
@MainActor
enum TableColumnRebuilder {

    static func apply(_ table: NSOutlineView,
                      target: [NodeColumn],
                      widths: [String: Double],
                      defaultWidths: [NodeColumn: CGFloat]) {
        let targetIDs = target.map(\.rawValue)
        let targetSet = Set(targetIDs)
        func id(_ column: NSTableColumn) -> String { column.identifier.rawValue }

        let current = table.tableColumns

        // A survivor the outline reference can be moved onto: the first
        // current column that stays in the target, else any current column
        // (a throwaway anchor for the rare "no overlap" case).
        let anchor = current.first { targetSet.contains(id($0)) } ?? current.first
        if let anchor, table.outlineTableColumn !== anchor {
            table.outlineTableColumn = anchor
        }

        for column in current where !targetSet.contains(id(column)) && column !== anchor {
            table.removeTableColumn(column)
        }

        if let anchor, !targetSet.contains(id(anchor)) {
            // No overlap at all (e.g. the name column was hidden): insert the
            // first target column, move the outline reference onto it, drop
            // the anchor. The outline column can then finally be removed.
            if let first = target.first {
                let newColumn = makeColumn(first, widths: widths, defaultWidths: defaultWidths)
                table.addTableColumn(newColumn)
                table.outlineTableColumn = newColumn
            }
            table.removeTableColumn(anchor)
        }

        var present = Set(table.tableColumns.map(id))
        for column in target where !present.contains(column.rawValue) {
            table.addTableColumn(makeColumn(column, widths: widths, defaultWidths: defaultWidths))
            present.insert(column.rawValue)
        }

        // Restore the target order.
        for (targetIndex, column) in target.enumerated() {
            if let currentIndex = table.tableColumns.firstIndex(where: { id($0) == column.rawValue }),
               currentIndex != targetIndex {
                table.moveColumn(currentIndex, toColumn: targetIndex)
            }
        }

        table.outlineTableColumn = table.tableColumns.first
        table.sizeLastColumnToFit()
    }

    private static func makeColumn(_ column: NodeColumn,
                                   widths: [String: Double],
                                   defaultWidths: [NodeColumn: CGFloat]) -> NSTableColumn {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
        // When sizes are combined the Size column carries both values.
        tableColumn.title = column == .size && ViewSettings.combinedSize
            ? String(localized: "Size / On disk")
            : column.title
        tableColumn.width = CGFloat(widths[column.rawValue] ?? defaultWidths[column] ?? 120)
        tableColumn.minWidth = 40
        tableColumn.maxWidth = 900
        // No sortDescriptorPrototype: header clicks are handled explicitly —
        // AppKit's automatic prototype cycling conflicts with it.
        return tableColumn
    }
}
