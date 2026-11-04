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
        return NodeRow(record.withSortKeys())
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

    func testNumericNameOrder() {
        XCTAssertEqual(SortKey.compare("file2", "file10"), .orderedAscending)
        XCTAssertEqual(SortKey.compare("file10", "file9"), .orderedDescending)
        // Same numeric value: keys are equal; the id tie-break keeps a stable order.
        XCTAssertEqual(SortKey.compare("file2", "file02"), .orderedSame)
        XCTAssertEqual(SortKey.compare("файл2", "файл10"), .orderedAscending)
    }

    func testFoldNormalizesCaseAndDiacritics() {
        XCTAssertEqual(SortKey.make("Éclair"), SortKey.make("eclair"))
        XCTAssertEqual(SortKey.compare("Banana", "Éclair"), .orderedAscending)
        // Combining marks are stripped, so "Ärger" folds to "arger" and sorts
        // like "Arger" — before "zebra".
        XCTAssertEqual(SortKey.compare("Ärger", "Zebra"), .orderedAscending)
    }

    func testV1SnapshotDecodesWithoutSortKeys() throws {
        // A record saved by schema v1 has no sort-key fields — decoding must
        // not fail, and withSortKeys() fills them.
        let json = #"{"id":1,"name":"Doc.pdf","relativePath":"Doc.pdf","isDirectory":false,"isHidden":false,"isSymlink":false,"isPackage":false,"notDownloaded":false}"#
        let decoder = JSONDecoder()
        let node = try decoder.decode(NodeRecord.self, from: Data(json.utf8))
        XCTAssertNil(node.nameSortKey)
        let filled = node.withSortKeys()
        XCTAssertEqual(filled.nameSortKey, "doc.pdf")
        XCTAssertEqual(filled.pathSortKey, "doc.pdf")
    }

    func testSortPerformance500k() {
        var rows: [NodeRow] = []
        rows.reserveCapacity(500_000)
        for i in 0..<500_000 {
            rows.append(row(Int64(i),
                            name: "file\(i % 997)-report\(i).txt",
                            kind: .file,
                            size: Int64(i)))
        }
        let start = Date()
        let sorted = RowSorting.apply(rows, sortOrder: [ColumnSort(column: .name, order: .forward)],
                                      foldersFirst: false)
        let elapsed = Date().timeIntervalSince(start)
        print("[benchmark] sort 500k rows by name took \(String(format: "%.2f", elapsed))s")
        XCTAssertLessThan(elapsed, 8.0, "sorting 500k rows must not hang")
        XCTAssertEqual(sorted.count, 500_000)
        // Sanity: result is non-decreasing by the comparator.
        for i in 1..<sorted.count {
            if SortKey.compare(sorted[i - 1].record.nameSortKey!, sorted[i].record.nameSortKey!) == .orderedDescending {
                XCTFail("order violated at \(i)")
                break
            }
        }
    }
}
