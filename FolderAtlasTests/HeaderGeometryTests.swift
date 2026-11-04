import XCTest
import AppKit
@testable import FolderAtlas

@MainActor
final class HeaderGeometryTests: XCTestCase {

    /// Table geometry for a custom headerView: the table sizes the header
    /// frame itself (regression guard — a zero-frame header disappears).
    func testTableSizesCustomHeaderView() {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        table.headerView = SortHeader(frame: NSRect(x: 0, y: 0, width: 800, height: 25))
        for (index, width) in [200.0, 300.0, 400.0].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            column.width = width
            table.addTableColumn(column)
        }
        table.sizeToFit()
        let header = try? XCTUnwrap(table.headerView as? SortHeader)
        XCTAssertNotNil(header)
        if let header {
            XCTAssertGreaterThan(header.frame.width, 0, "header must be visible")
        }
    }

    /// Border detection must follow rect(ofColumn:) geometry: column bodies
    /// sort, edges and gaps do not.
    func testBorderDetectionMatchesColumnRects() {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let header = SortHeader(frame: NSRect(x: 0, y: 0, width: 800, height: 25))
        table.headerView = header
        for (index, width) in [200.0, 300.0, 400.0].enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(index)"))
            column.width = width
            table.addTableColumn(column)
        }
        table.sizeToFit()

        let r0 = table.rect(ofColumn: 0)
        let body0 = (r0.minX + r0.maxX) / 2
        XCTAssertFalse(header.isOnColumnBorder(NSPoint(x: body0, y: 10)), "column body sorts")
        XCTAssertTrue(header.isOnColumnBorder(NSPoint(x: r0.maxX, y: 10)), "divider does not sort")
        XCTAssertTrue(header.isOnColumnBorder(NSPoint(x: r0.maxX - 3, y: 10)), "just inside divider")
        XCTAssertTrue(header.isOnColumnBorder(NSPoint(x: r0.maxX + 3, y: 10)), "just outside divider")
        let r1 = table.rect(ofColumn: 1)
        let body1 = (r1.minX + r1.maxX) / 2
        XCTAssertFalse(header.isOnColumnBorder(NSPoint(x: body1, y: 10)), "second column body sorts")
    }
}
