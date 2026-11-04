import XCTest
@testable import FolderAtlas

/// P2.7 column-clarity checks (owner feedback): resolution naming, full
/// labels in the picker, folder size removed from the picker, combined
/// size/on-disk formatting, absolute path helper.
final class ColumnClarityTests: XCTestCase {

    func testPickerCasesExcludeFolderSize() {
        XCTAssertFalse(NodeColumn.pickerCases.contains(.folderSize), "folder size is not a picker item")
        XCTAssertTrue(NodeColumn.pickerCases.contains(.size))
        XCTAssertTrue(NodeColumn.pickerCases.contains(.absolutePath), "absolute path is offered next to path")
    }

    func testFullMenuLabelsForCountColumns() {
        XCTAssertNotEqual(NodeColumn.items.menuTitle, NodeColumn.items.title,
                          "the picker must explain what Items counts")
        XCTAssertNotEqual(NodeColumn.nestedItems.menuTitle, NodeColumn.nestedItems.title,
                          "the picker must explain what Nested items counts")
        XCTAssertEqual(NodeColumn.kind.menuTitle, NodeColumn.kind.title,
                       "columns without ambiguity keep the same label")
    }

    func testCombinedSizeFormatting() {
        XCTAssertEqual(Fmt.sizeCombined(1_048_576, 2_097_152, combined: true),
                       "\(Fmt.size(1_048_576)) / \(Fmt.size(2_097_152))")
        XCTAssertEqual(Fmt.sizeCombined(1_048_576, 2_097_152, combined: false),
                       Fmt.size(1_048_576), "combination off → plain size")
        XCTAssertEqual(Fmt.sizeCombined(1_048_576, nil, combined: true),
                       Fmt.size(1_048_576), "unknown on-disk → plain size")
    }

    func testAbsolutePathString() {
        XCTAssertEqual(NodeColumn.absolutePathString(root: "/Users/x/Proj", relativePath: "a/b.txt"),
                       "/Users/x/Proj/a/b.txt")
        XCTAssertEqual(NodeColumn.absolutePathString(root: "/Users/x/Proj", relativePath: ""),
                       "/Users/x/Proj")
        XCTAssertEqual(NodeColumn.absolutePathString(root: "", relativePath: "a.txt"),
                       "a.txt", "no root → relative falls through")
    }

    func testSortComparatorHandlesAbsolutePath() {
        let a = testRecord("a", relativePath: "a.txt")
        let b = testRecord("b", relativePath: "b.txt")
        let rowA = NodeRow(a)
        let rowB = NodeRow(b)
        let sort = ColumnSort(column: .absolutePath, order: .forward)
        XCTAssertEqual(sort.compare(rowA, rowB), .orderedAscending)
        XCTAssertEqual(sort.compare(rowB, rowA), .orderedDescending)
    }

    // MARK: helpers

    private func testRecord(_ id: String, relativePath: String) -> NodeRecord {
        NodeRecord(
            id: Int64(abs(id.hashValue % 1_000_000)) + 1,
            name: id,
            relativePath: relativePath,
            ext: nil,
            isDirectory: false,
            isHidden: false,
            isSymlink: false,
            isPackage: false,
            size: 10,
            dirSize: nil,
            notDownloaded: false,
            error: nil)
    }
}
