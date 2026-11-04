import XCTest
@testable import FolderAtlas

/// Sorting behaviour of table/outline rows.
final class RowSortingTests: XCTestCase {

    private func row(_ id: Int64, name: String, kind: NodeKind, size: Int64? = 0) -> NodeRow {
        let record = NodeRecord(id: id, parentID: nil, name: name, relativePath: name,
                                ext: kind == .file ? "txt" : nil,
                                isDirectory: kind == .folder || kind == .package,
                                isHidden: false, isSymlink: kind == .symlink,
                                isPackage: kind == .package,
                                size: size, allocSize: nil, created: nil, modified: nil,
                                notDownloaded: false)
        return NodeRow(record)
    }

    func testFoldersFirstGroupsFoldersAboveFiles() {
        let rows = [
            row(1, name: "zeta.txt", kind: .file),
            row(2, name: "alpha", kind: .folder),
            row(3, name: "beta.txt", kind: .file),
            row(4, name: "App", kind: .package)
        ]
        let sorted = RowSorting.apply(rows, sortOrder: [ColumnSort(column: .name, order: .forward)],
                                      foldersFirst: true)
        XCTAssertEqual(sorted.map(\.record.name), ["alpha", "App", "beta.txt", "zeta.txt"])

        let plain = RowSorting.apply(rows, sortOrder: [ColumnSort(column: .name, order: .forward)],
                                     foldersFirst: false)
        XCTAssertEqual(plain.map(\.record.name), ["alpha", "App", "beta.txt", "zeta.txt"])
    }

    func testFoldersFirstRespectsSortOrderWithinGroups() {
        let rows = [
            row(1, name: "folder-b", kind: .folder),
            row(2, name: "file-a", kind: .file, size: 100),
            row(3, name: "folder-a", kind: .folder),
            row(4, name: "file-b", kind: .file, size: 5)
        ]
        // Size descending: within the folder group nothing changes (sizes equal),
        // within the file group the larger file comes first.
        let sorted = RowSorting.apply(rows, sortOrder: [ColumnSort(column: .size, order: .reverse)],
                                      foldersFirst: true)
        let names = sorted.map(\.record.name)
        XCTAssertEqual(names.prefix(2).sorted(), ["folder-a", "folder-b"])
        XCTAssertEqual(Array(names.suffix(2)), ["file-a", "file-b"])
    }

    func testEmptySortOrderFallsBackToName() {
        let rows = [row(3, name: "c", kind: .file), row(1, name: "a", kind: .file), row(2, name: "b", kind: .file)]
        let sorted = RowSorting.apply(rows, sortOrder: [], foldersFirst: false)
        XCTAssertEqual(sorted.map(\.record.name), ["a", "b", "c"])
    }

    func testReverseOrderFlips() {
        let rows = [row(1, name: "a", kind: .file), row(2, name: "b", kind: .file)]
        let sorted = RowSorting.apply(rows, sortOrder: [ColumnSort(column: .name, order: .reverse)],
                                      foldersFirst: false)
        XCTAssertEqual(sorted.map(\.record.name), ["b", "a"])
    }
}
