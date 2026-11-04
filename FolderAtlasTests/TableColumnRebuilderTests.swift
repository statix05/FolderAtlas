import XCTest
import AppKit
@testable import FolderAtlas

/// TableColumnRebuilder regression tests. The historical bug: NSOutlineView
/// refuses to remove its outline column via removeTableColumn:, so the old
/// rebuild (remove-all + re-add) duplicated the "Имя" column and pinned it
/// first. AppKit even logs: "cannot remove outlineTableColumn".
@MainActor
final class TableColumnRebuilderTests: XCTestCase {

    private let defaultWidths: [NodeColumn: CGFloat] = [.name: 260, .kind: 90, .ext: 70, .size: 100]

    private func makeTable(columns: [NodeColumn], outline: NodeColumn?) -> NSOutlineView {
        let table = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        for column in columns {
            table.addTableColumn(makeColumn(column))
        }
        if let outline {
            table.outlineTableColumn = table.tableColumns.first { $0.identifier.rawValue == outline.rawValue }
        }
        return table
    }

    private func makeColumn(_ column: NodeColumn) -> NSTableColumn {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
        tableColumn.title = column.title
        return tableColumn
    }

    private func apply(_ table: NSOutlineView, _ target: [NodeColumn]) {
        TableColumnRebuilder.apply(table, target: target, widths: [:], defaultWidths: defaultWidths)
    }

    private func identifiers(_ table: NSOutlineView) -> [String] {
        table.tableColumns.map(\.identifier.rawValue)
    }

    func testAddAndRemoveColumnsWithoutDuplicates() {
        let table = makeTable(columns: [.name, .kind, .ext], outline: .name)
        apply(table, [.name, .kind, .size])
        XCTAssertEqual(identifiers(table), ["name", "kind", "size"], "no duplicates, order matches target")
        XCTAssertEqual(table.outlineTableColumn?.identifier.rawValue, "name")
    }

    /// Owner scenario: Тип dragged first, then a column toggled — Имя must
    /// stay where the target says, not teleport to first, and not duplicate.
    func testNonFirstOutlineColumnStaysPut() {
        let table = makeTable(columns: [.name, .kind, .ext], outline: .name)
        apply(table, [.kind, .name, .size])
        XCTAssertEqual(identifiers(table), ["kind", "name", "size"], "target order preserved")
    }

    /// Hiding the name column entirely must be possible (outline repointed).
    func testHidingNameColumn() {
        let table = makeTable(columns: [.name, .kind, .size], outline: .name)
        apply(table, [.kind, .size])
        XCTAssertEqual(identifiers(table), ["kind", "size"], "name removed cleanly")
        XCTAssertEqual(table.outlineTableColumn?.identifier.rawValue, "kind")
        // And restoring it must not duplicate anything.
        apply(table, [.name, .kind, .size])
        XCTAssertEqual(Set(identifiers(table)).count, identifiers(table).count)
    }

    /// The no-overlap corner case: nothing of the target is on the table yet.
    func testNoOverlapRebuild() {
        let table = makeTable(columns: [.name], outline: .name)
        apply(table, [.kind, .size])
        XCTAssertEqual(identifiers(table), ["kind", "size"], "anchor dropped, target built")
        XCTAssertEqual(table.outlineTableColumn?.identifier.rawValue, "kind")
    }

    func testEmptyTargetClearsExceptNothing() {
        let table = makeTable(columns: [.name, .kind], outline: .name)
        apply(table, [.name])
        XCTAssertEqual(identifiers(table), ["name"])
    }
}
