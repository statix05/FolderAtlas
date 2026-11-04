import XCTest
@testable import FolderAtlas

@MainActor
final class ColumnFitTests: XCTestCase {

    private func record(_ id: Int64, name: String, kind: NodeKind = .file, ext: String? = nil) -> NodeRecord {
        NodeRecord(
            id: id, name: name, relativePath: name, ext: ext,
            isDirectory: kind == .folder || kind == .package,
            isHidden: false, isSymlink: kind == .symlink, isPackage: kind == .package,
            size: 100, dirSize: nil, notDownloaded: false, error: nil)
    }

    func testFittedWidthScalesWithLongestName() throws {
        let rows = [record(1, name: "a"), record(2, name: "abcdefghij")]
        let w = try XCTUnwrap(ColumnFit.fittedWidth(for: .name, rows: rows))
        let wLong = try XCTUnwrap(ColumnFit.fittedWidth(
            for: .name, rows: rows + [record(3, name: "abcdefghij_longer_name_here")]))
        XCTAssertGreaterThan(wLong, w, "longer name must increase fitted width")
        XCTAssertGreaterThanOrEqual(w, 40, "minimum width")
    }

    func testFittedWidthCappedAt900() throws {
        let long = String(repeating: "W", count: 5000)
        let w = try XCTUnwrap(ColumnFit.fittedWidth(for: .name, rows: [record(1, name: long)]))
        XCTAssertEqual(w, 900, "fitted width capped at 900")
    }

    func testEmptyRowsReturnNil() {
        XCTAssertNil(ColumnFit.fittedWidth(for: .name, rows: []))
    }

    func testFlagsColumnNeedsNoMeasurement() {
        XCTAssertNil(ColumnFit.fittedWidth(for: .flags, rows: [record(1, name: "a")]))
    }
}
