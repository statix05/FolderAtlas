import Foundation

enum StoreError: LocalizedError {
    case notFound
    case corrupted(String)
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .notFound: return String(localized: "The saved map was not found.")
        case .corrupted(let detail): return String(localized: "The saved map is corrupted.") + " (\(detail))"
        case .newerVersion(let version):
            return String(localized: "The map was saved by a newer version of FolderAtlas.") + " (schema \(version))"
        }
    }
}

/// Local storage of folder maps.
///
/// Format: one NDJSON file per snapshot (`.foldermap`). Line 1 is the JSON header,
/// every following line is one `NodeRecord`. The format is human readable, streams
/// well, needs no external dependency and is written atomically (tmp file + rename).
/// `schemaVersion` in the header drives migrations on load.
enum SnapshotStore {

    static var baseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appending(path: "FolderAtlas", directoryHint: .isDirectory)
        let snapshots = base.appending(path: "Snapshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        return snapshots
    }

    static func url(for id: UUID) -> URL {
        baseURL.appending(path: id.uuidString + ".foldermap")
    }

    static func save(_ snapshot: Snapshot) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var data = try encoder.encode(snapshot.header)
        data.append(0x0A)
        for node in snapshot.nodes {
            data.append(try encoder.encode(node))
            data.append(0x0A)
        }
        let target = url(for: snapshot.header.id)
        try data.write(to: target, options: [.atomic])
        return target
    }

    static func load(id: UUID) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let fileURL = url(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw StoreError.notFound }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { throw StoreError.corrupted("empty") }
        let headerLine = lines.removeFirst()
        guard let header = try? decoder.decode(SnapshotHeader.self, from: Data(headerLine.utf8)) else {
            throw StoreError.corrupted("header")
        }
        if header.schemaVersion > SnapshotHeader.schemaVersion {
            throw StoreError.newerVersion(header.schemaVersion)
        }
        var nodes: [NodeRecord] = []
        nodes.reserveCapacity(max(16, header.fileCount + header.folderCount + 1))
        for line in lines {
            if let node = try? decoder.decode(NodeRecord.self, from: Data(line.utf8)) {
                nodes.append(node)
            }
        }
        // Migration point: when schemaVersion < current, transform here.
        return Snapshot(header: header, nodes: nodes)
    }

    /// Cheap index of saved maps: reads only the header line of each file.
    static func list() -> [SnapshotHeader] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles)) ?? []
        var headers: [SnapshotHeader] = []
        for file in files where file.pathExtension == "foldermap" {
            if let header = readHeader(of: file) { headers.append(header) }
        }
        return headers.sorted { $0.createdAt > $1.createdAt }
    }

    static func readHeader(of fileURL: URL) -> SnapshotHeader? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 1 << 16), !chunk.isEmpty else { return nil }
        guard let newlineIndex = chunk.firstIndex(of: 0x0A) else { return nil }
        let headerData = chunk[chunk.startIndex..<newlineIndex]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(SnapshotHeader.self, from: Data(headerData))
    }

    static func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    static func rename(id: UUID, to name: String) throws {
        var snapshot = try load(id: id)
        snapshot.header.displayName = name
        try save(snapshot)
    }

    /// All snapshots that share the same source path (for history and diffing).
    static func history(ofSource sourcePath: String) -> [SnapshotHeader] {
        list().filter { $0.sourcePath == sourcePath }
    }
}
