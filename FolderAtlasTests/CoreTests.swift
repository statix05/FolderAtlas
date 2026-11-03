import XCTest
@testable import FolderAtlas

final class CoreTests: XCTestCase {

    // MARK: - Snapshot store roundtrip

    private func makeSnapshot(fileCount: Int = 3) -> Snapshot {
        var nodes: [NodeRecord] = []
        nodes.append(NodeRecord(id: 0, parentID: nil, name: "Мои документы", relativePath: "",
                                ext: nil, isDirectory: true, isHidden: false, isSymlink: false,
                                isPackage: false, size: nil, allocSize: nil, created: Date(timeIntervalSince1970: 1),
                                modified: Date(timeIntervalSince1970: 2), tags: ["Work"],
                                childCount: 3, descendantCount: 3, dirSize: 9, notDownloaded: false))
        for index in 1...Int64(fileCount) {
            nodes.append(NodeRecord(id: index, parentID: 0, name: "файл-\(index) ✅.txt",
                                    relativePath: "файл-\(index) ✅.txt", ext: "txt",
                                    isDirectory: false, isHidden: false, isSymlink: false, isPackage: false,
                                    size: index, allocSize: index * 4096,
                                    created: Date(timeIntervalSince1970: 100 + Double(index)),
                                    modified: Date(timeIntervalSince1970: 200 + Double(index)),
                                    tags: index == 1 ? ["Work", "Important"] : nil, notDownloaded: false))
        }
        let header = SnapshotHeader(displayName: "Test Map", sourcePath: "/tmp/source",
                                    scanSettings: ScanConfiguration(), fileCount: fileCount,
                                    folderCount: 1, errorCount: 0, totalSize: 9, durationSeconds: 0.5)
        return Snapshot(header: header, nodes: nodes)
    }

    func testStoreRoundtripAndHistory() throws {
        let snapshot = makeSnapshot()
        let url = try SnapshotStore.save(snapshot)
        defer { try? SnapshotStore.delete(id: snapshot.header.id) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = try SnapshotStore.load(id: snapshot.header.id)
        XCTAssertEqual(loaded.header, snapshot.header)
        XCTAssertEqual(loaded.nodes.count, snapshot.nodes.count)
        XCTAssertEqual(loaded.nodes[1].name, "файл-1 ✅.txt")
        XCTAssertEqual(loaded.nodes[1].tags, ["Work", "Important"])
        XCTAssertEqual(loaded.children(of: 0).count, 3)

        // Header-only listing must see the new map.
        let listed = SnapshotStore.list()
        XCTAssertTrue(listed.contains { $0.id == snapshot.header.id })

        try SnapshotStore.rename(id: snapshot.header.id, to: "Renamed")
        let renamed = try SnapshotStore.load(id: snapshot.header.id)
        XCTAssertEqual(renamed.header.displayName, "Renamed")

        try SnapshotStore.delete(id: snapshot.header.id)
        XCTAssertThrowsError(try SnapshotStore.load(id: snapshot.header.id))
    }

    // MARK: - Filters

    func testFilterCriteria() {
        var nodes: [NodeRecord] = []
        nodes.append(NodeRecord(id: 0, parentID: nil, name: "root", relativePath: "", ext: nil,
                                isDirectory: true, isHidden: false, isSymlink: false, isPackage: false,
                                size: nil, allocSize: nil, created: nil, modified: nil, notDownloaded: false))
        nodes.append(NodeRecord(id: 1, parentID: 0, name: "report.pdf", relativePath: "report.pdf", ext: "pdf",
                                isDirectory: false, isHidden: false, isSymlink: false, isPackage: false,
                                size: 5_000_000, allocSize: nil,
                                created: Date(timeIntervalSince1970: 1000), modified: Date(timeIntervalSince1970: 2000),
                                tags: ["Work"], notDownloaded: false))
        nodes.append(NodeRecord(id: 2, parentID: 0, name: ".dotfile", relativePath: ".dotfile", ext: nil,
                                isDirectory: false, isHidden: true, isSymlink: false, isPackage: false,
                                size: 10, allocSize: nil, created: nil, modified: nil, notDownloaded: false))

        var filter = FilterCriteria()
        XCTAssertTrue(filter.matches(nodes[1]))
        XCTAssertTrue(filter.matches(nodes[0]))

        filter.kinds = [.files]
        XCTAssertTrue(filter.matches(nodes[1]))
        XCTAssertFalse(filter.matches(nodes[0]))

        filter = FilterCriteria()
        filter.extensions = ["pdf"]
        XCTAssertTrue(filter.matches(nodes[1]))
        XCTAssertFalse(filter.matches(nodes[2]))

        filter = FilterCriteria()
        filter.minSize = 1_000_000
        XCTAssertTrue(filter.matches(nodes[1]))
        XCTAssertFalse(filter.matches(nodes[2]))

        filter = FilterCriteria()
        filter.modifiedFrom = Date(timeIntervalSince1970: 1500)
        XCTAssertTrue(filter.matches(nodes[1]))
        XCTAssertFalse(filter.matches(nodes[2]))

        filter = FilterCriteria()
        filter.tags = ["Work"]
        XCTAssertTrue(filter.matches(nodes[1]))
        XCTAssertFalse(filter.matches(nodes[2]))

        filter = FilterCriteria()
        filter.searchText = "REPORT"
        XCTAssertTrue(filter.matches(nodes[1])) // localizedStandardContains is case-insensitive
        XCTAssertFalse(filter.matches(nodes[2]))

        filter = FilterCriteria()
        filter.hiddenMode = .onlyHidden
        XCTAssertFalse(filter.matches(nodes[1]))
        XCTAssertTrue(filter.matches(nodes[2]))
    }

    // MARK: - Diff

    func testDiffAddedRemovedChangedMoved() {
        func node(_ path: String, size: Int64, created: Date, hash: String? = nil) -> NodeRecord {
            let name = (path as NSString).lastPathComponent
            return NodeRecord(id: 0, parentID: nil, name: name, relativePath: path,
                              ext: NodeRecord.extensionOf(name), isDirectory: false, isHidden: false,
                              isSymlink: false, isPackage: false, size: size, allocSize: nil,
                              created: created, modified: created, sha256: hash, notDownloaded: false)
        }
        let date = Date(timeIntervalSince1970: 5000)
        let oldNodes = [
            node("kept.txt", size: 10, created: date),
            node("removed.txt", size: 20, created: date),
            node("changed.txt", size: 30, created: date),
            node("old place/moved.txt", size: 40, created: date, hash: "aa")
        ]
        let newNodes = [
            node("kept.txt", size: 10, created: date),
            node("added.txt", size: 50, created: date),
            node("changed.txt", size: 33, created: date),
            node("new place/renamed.txt", size: 40, created: date, hash: "aa")
        ]
        let header = SnapshotHeader(displayName: "a", sourcePath: "/s", scanSettings: ScanConfiguration(),
                                    fileCount: 0, folderCount: 0, errorCount: 0, totalSize: 0, durationSeconds: 0)
        let report = SnapshotDiff.compare(old: Snapshot(header: header, nodes: oldNodes),
                                          new: Snapshot(header: header, nodes: newNodes))

        XCTAssertEqual(Set(report.added.map(\.path)), ["added.txt"])
        XCTAssertEqual(Set(report.removed.map(\.path)), ["removed.txt"])
        XCTAssertEqual(Set(report.changed.map(\.path)), ["changed.txt"])
        XCTAssertEqual(report.moved.count, 1)
        XCTAssertEqual(report.moved.first?.current?.relativePath, "new place/renamed.txt")
        XCTAssertEqual(report.moved.first?.movedFrom, "old place/moved.txt")
        XCTAssertEqual(report.moved.first?.confidence, .high)
        XCTAssertTrue(report.moved.allSatisfy { $0.current?.sha256 == "aa" })

        // Without checksums the heuristic falls back to dates + extension.
        let oldNoHash = Snapshot(header: header, nodes: oldNodes.map { var n = $0; n.sha256 = nil; return n })
        let newNoHash = Snapshot(header: header, nodes: newNodes.map { var n = $0; n.sha256 = nil; return n })
        let report2 = SnapshotDiff.compare(old: oldNoHash, new: newNoHash)
        XCTAssertEqual(report2.moved.count, 1)
        XCTAssertEqual(report2.moved.first?.confidence, .medium)
    }

    // MARK: - Duplicates

    func testDuplicateFinderGroupsByContent() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fa-dupe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "same content".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try "same content".write(to: dir.appending(path: "b.txt"), atomically: true, encoding: .utf8)
        try "other".write(to: dir.appending(path: "c.txt"), atomically: true, encoding: .utf8)

        let scan = try await ScanEngine.run(root: dir, config: ScanConfiguration())
        let report = await DuplicateFinder.find(in: scan.nodes, sourceRoot: dir)
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups.first?.nodes.count, 2)
        XCTAssertEqual(report.groups.first?.size, Int64("same content".utf8.count))
        XCTAssertEqual(report.hashedCount, 2) // only the same-size candidates get hashed
    }

    // MARK: - CSV / TSV

    func testCSVEscapingAndFormulaGuard() {
        let node = NodeRecord(id: 1, parentID: nil, name: "=cmd|' /C calc'!A0\nnext", relativePath: "x",
                              ext: nil, isDirectory: false, isHidden: false, isSymlink: false, isPackage: false,
                              size: 5, allocSize: nil, created: nil, modified: nil, notDownloaded: false)
        let snapshot = makeSnapshot()
        let options = ExportOptions()
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let row = builder.cell(.name, node)
        let data = TextExporters.delimited(rows: [RowBuilder.Row(cells: [row], node: node)],
                                           totals: nil, columns: [.name], separator: ",", bom: false)
        let text = String(data: data, encoding: .utf8)!
        // Guard apostrophe + quoting (the field contains a newline, so it is quoted
        // as a whole; the closing quote follows the embedded newline).
        XCTAssertTrue(text.contains("\"'=cmd|' /C calc'!A0"))
        XCTAssertTrue(text.contains("next\""))
        XCTAssertFalse(text.hasPrefix("\u{FEFF}"))

        let withBOM = TextExporters.delimited(rows: [], totals: nil, columns: [.name], separator: ",", bom: true)
        // String(data:encoding:) strips the BOM when decoding — check raw bytes.
        XCTAssertEqual(Array(withBOM.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testMinusPrefixIsGuarded() {
        XCTAssertEqual(TextExporters.guardAgainstFormulas("-2+3"), "'-2+3")
        XCTAssertEqual(TextExporters.guardAgainstFormulas("=HYPERLINK(1)"), "'=HYPERLINK(1)")
        XCTAssertEqual(TextExporters.guardAgainstFormulas("plain"), "plain")
    }

    // MARK: - JSON

    func testJSONExportParses() throws {
        let snapshot = makeSnapshot()
        var options = ExportOptions()
        options.columns = [.name, .size]
        options.humanReadable = false
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let data = try TextExporters.json(header: snapshot.header, columns: options.columns,
                                          rows: builder.rows(), options: options)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 3) // the scan root itself is not exported
        let firstFile = rows.first { ($0["name"] as? String)?.contains("файл-1") == true }
        XCTAssertEqual(firstFile?["size"] as? Double, 1)
    }

    // MARK: - ZIP / XLSX

    func testZipWriterProducesValidArchive() throws {
        let target = FileManager.default.temporaryDirectory.appending(path: "fa-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: target) }
        let payload = Data("folder atlas zip entry".utf8)
        try ZipWriter.write(entries: [
            ZipWriter.Entry(name: "folder/a.txt", data: payload),
            ZipWriter.Entry(name: "b.xml", data: Data("<x/>".utf8))
        ], to: target)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", target.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip -t must validate the archive")
    }

    func testXLSXExportIsValidZipWithSheet() throws {
        let snapshot = makeSnapshot()
        var options = ExportOptions()
        options.columns = [.name, .kind, .size]
        options.humanReadable = false
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let data = try XLSXExporter.export(header: snapshot.header, columns: options.columns,
                                           rows: builder.rows(), totals: builder.totalsRow(for: builder.rows()),
                                           options: options)
        // A real ZIP container: local file header magic "PK\x03\x04".
        XCTAssertEqual([UInt8](data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])

        let target = FileManager.default.temporaryDirectory.appending(path: "fa-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: target) }
        try data.write(to: target)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", target.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let listing = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(listing.contains("xl/workbook.xml"))
        XCTAssertTrue(listing.contains("xl/worksheets/sheet1.xml"))
    }

    // MARK: - HTML / PDF / Markdown

    func testHTMLExportIsStandalone() throws {
        let snapshot = makeSnapshot()
        var options = ExportOptions()
        options.columns = [.name, .pathAbsolute]
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let data = try HTMLExporter.export(header: snapshot.header, columns: options.columns,
                                           rows: builder.rows(), totals: builder.totalsRow(for: builder.rows()),
                                           options: options)
        let html = String(data: data, encoding: .utf8)!
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("prefers-color-scheme"))
        XCTAssertFalse(html.contains("http://cdn"), "must not reference external resources")
        XCTAssertFalse(html.contains("<link"), "no external stylesheets")
        XCTAssertFalse(html.contains("<script src"), "no external scripts")
    }

    func testPDFExportProducesPDF() {
        let snapshot = makeSnapshot()
        var options = ExportOptions()
        options.columns = [.name, .size]
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let data = PDFExporter.export(header: snapshot.header, columns: options.columns,
                                      rows: builder.rows(), totals: builder.totalsRow(for: builder.rows()))
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
    }

    func testMarkdownExportEscapesPipes() {
        let node = NodeRecord(id: 1, parentID: nil, name: "a|b", relativePath: "a|b", ext: nil,
                              isDirectory: false, isHidden: false, isSymlink: false, isPackage: false,
                              size: 1, allocSize: nil, created: nil, modified: nil, notDownloaded: false)
        let snapshot = makeSnapshot()
        var options = ExportOptions()
        options.columns = [.name]
        let builder = RowBuilder(snapshot: snapshot, options: options, filter: FilterCriteria(), selection: [])
        let row = RowBuilder.Row(cells: [builder.cell(.name, node)], node: node)
        let data = TextExporters.markdown(rows: [row],
                                          totals: nil, columns: [.name])
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("a\\|b"))
    }
}
