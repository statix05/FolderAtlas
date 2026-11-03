import XCTest
@testable import FolderAtlas

/// Builds a fixture tree in a temporary directory and runs real scans on it.
final class ScanTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "folderatlas-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try "1234567890".write(to: root.appending(path: "файл ✅ тест.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: root.appending(path: ".hidden.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appending(path: "EmptyDir"), withIntermediateDirectories: true)

        let sub = root.appending(path: "Sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "aaaa".write(to: sub.appending(path: "one.bin"), atomically: true, encoding: .utf8)
        try "bb".write(to: sub.appending(path: "two.txt"), atomically: true, encoding: .utf8)
        try "cc".write(to: sub.appending(path: "three.md"), atomically: true, encoding: .utf8)

        let deep = sub.appending(path: "l1/l2/l3/l4/l5")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try "deep".write(to: deep.appending(path: "leaf.txt"), atomically: true, encoding: .utf8)

        // A fake package with contents.
        let app = root.appending(path: "Demo.app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        try "MachO".write(to: app.appending(path: "Contents/MacOS/demo"), atomically: true, encoding: .utf8)

        // A directory the scanner cannot read.
        let noperm = root.appending(path: "noperm")
        try FileManager.default.createDirectory(at: noperm, withIntermediateDirectories: true)
        try "secret".write(to: noperm.appending(path: "secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: noperm.path)
    }

    override func tearDownWithError() throws {
        if let root {
            // Restore permissions so cleanup succeeds, then remove everything.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: root.appending(path: "noperm").path)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func scan(_ config: ScanConfiguration = ScanConfiguration()) async throws -> ScanOutput {
        try await ScanEngine.run(root: root, config: config)
    }

    func testScanCountsAndMetadata() async throws {
        let output = try await scan()
        XCTAssertFalse(output.cancelled)
        XCTAssertGreaterThan(output.nodes.count, 5)

        // Dense ids: nodes[i].id == i, parents remapped consistently.
        for (index, node) in output.nodes.enumerated() {
            XCTAssertEqual(node.id, Int64(index))
            if let parent = node.parentID {
                XCTAssertLessThan(parent, node.id)
            }
        }

        let names = Set(output.nodes.map(\.name))
        XCTAssertTrue(names.contains("файл ✅ тест.txt"))
        XCTAssertTrue(names.contains(".hidden.txt"))
        XCTAssertTrue(names.contains("EmptyDir"))

        let file = output.nodes.first { $0.name == "файл ✅ тест.txt" }!
        XCTAssertEqual(file.size, 10)
        XCTAssertEqual(file.ext, "txt")
        XCTAssertFalse(file.isDirectory)
        XCTAssertNotNil(file.created)
        XCTAssertNotNil(file.modified)

        let hidden = output.nodes.first { $0.name == ".hidden.txt" }!
        XCTAssertTrue(hidden.isHidden)

        let emptyDir = output.nodes.first { $0.name == "EmptyDir" }!
        XCTAssertTrue(emptyDir.isDirectory)
        XCTAssertEqual(emptyDir.childCount, 0)

        let sub = output.nodes.first { $0.name == "Sub" }!
        XCTAssertNotNil(sub.childCount)
        XCTAssertEqual(sub.childCount!, 4) // one.bin, two.txt, three.md, l1
        // Recursive folder size = sum of descendant file logical sizes (4+2+2+4 bytes).
        XCTAssertEqual(sub.dirSize ?? -1, 12)

        let leaf = output.nodes.first { $0.name == "leaf.txt" }!
        XCTAssertEqual(leaf.size, 4)
        XCTAssertEqual(leaf.relativePath, "Sub/l1/l2/l3/l4/l5/leaf.txt")
    }

    func testSymlinksAreRecordedAndNeverFollowed() async throws {
        let fileURL = root.appending(path: "файл ✅ тест.txt")
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: "link-to-file").path,
                                                   withDestinationPath: fileURL.path)
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: "loop").path,
                                                   withDestinationPath: root.path)

        let output = try await scan()
        let link = output.nodes.first { $0.name == "link-to-file" }
        XCTAssertNotNil(link)
        XCTAssertEqual(link!.kind, .symlink)
        XCTAssertFalse(link!.isDirectory)

        // The parent-link must not explode the tree with a second copy of root contents.
        let rootCopies = output.nodes.filter { $0.name == root.lastPathComponent && !$0.isDirectory }
        XCTAssertTrue(rootCopies.isEmpty)
        // And no node lives under "loop/".
        XCTAssertNil(output.nodes.first { $0.relativePath.hasPrefix("loop/") })
    }

    func testPackageContentsToggle() async throws {
        let including = try await scan(ScanConfiguration(includePackageContents: true))
        XCTAssertNotNil(including.nodes.first { $0.name == "demo" && $0.relativePath == "Demo.app/Contents/MacOS/demo" })
        let appPackage = including.nodes.first { $0.name == "Demo.app" }
        XCTAssertEqual(appPackage?.kind, .package)

        let boundary = try await scan(ScanConfiguration(includePackageContents: false))
        XCTAssertNil(boundary.nodes.first { $0.relativePath == "Demo.app/Contents/MacOS/demo" })
        XCTAssertNotNil(boundary.nodes.first { $0.name == "Demo.app" })
    }

    func testHiddenFilesToggle() async throws {
        let including = try await scan(ScanConfiguration(includeHidden: true))
        XCTAssertNotNil(including.nodes.first { $0.name == ".hidden.txt" })
        let excluding = try await scan(ScanConfiguration(includeHidden: false))
        XCTAssertNil(excluding.nodes.first { $0.name == ".hidden.txt" })
    }

    func testUnreadableDirectoryIsRecordedNotFatal() async throws {
        let output = try await scan()
        XCTAssertGreaterThanOrEqual(output.stats.errorCount, 1)
        let broken = output.nodes.first { $0.name == "noperm" }
        XCTAssertNotNil(broken)
        XCTAssertNotNil(broken!.error)
        // The scan itself still produced the rest of the tree.
        XCTAssertNotNil(output.nodes.first { $0.name == "файл ✅ тест.txt" })
    }

    func testEmptyScan() async throws {
        let empty = FileManager.default.temporaryDirectory
            .appending(path: "folderatlas-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let output = try await ScanEngine.run(root: empty, config: ScanConfiguration())
        XCTAssertEqual(output.nodes.count, 1) // just the root
        XCTAssertEqual(output.stats.fileCount, 0)
        XCTAssertFalse(output.cancelled)
    }

    func testCancellation() async throws {
        let rootURL = root!
        let task = Task { try await ScanEngine.run(root: rootURL, config: ScanConfiguration()) }
        task.cancel()
        let output = try await task.value
        XCTAssertTrue(output.cancelled)
    }

    func testProgressEventsArrive() async throws {
        final class EventBox: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            func mark() { lock.lock(); finished = true; lock.unlock() }
            var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
        }
        let box = EventBox()
        let output = try await ScanEngine.run(root: root, config: ScanConfiguration()) { event in
            if event.finished {
                box.mark()
            }
        }
        XCTAssertFalse(output.cancelled)
        XCTAssertTrue(box.isFinished, "the finished progress event must be delivered")
    }
}
