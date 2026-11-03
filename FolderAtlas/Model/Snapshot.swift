import Foundation

/// Header of a saved snapshot — metadata about the scan, not the nodes.
struct SnapshotHeader: Codable, Sendable, Hashable, Identifiable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var createdAt: Date
    var displayName: String
    /// Absolute path of the scanned source (stored for reference only).
    var sourcePath: String
    var scanSettings: ScanConfiguration
    var fileCount: Int
    var folderCount: Int
    var errorCount: Int
    var totalSize: Int64
    var durationSeconds: Double

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         displayName: String,
         sourcePath: String,
         scanSettings: ScanConfiguration,
         fileCount: Int,
         folderCount: Int,
         errorCount: Int,
         totalSize: Int64,
         durationSeconds: Double) {
        self.schemaVersion = SnapshotHeader.schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.displayName = displayName
        self.sourcePath = sourcePath
        self.scanSettings = scanSettings
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.errorCount = errorCount
        self.totalSize = totalSize
        self.durationSeconds = durationSeconds
    }
}

/// An in-memory folder map: header plus a flat array of nodes.
///
/// `nodes[i].id == Int64(i)` always holds — ids are dense array indexes.
/// `childrenIndex` maps a parent id to its direct children ids, sorted by
/// localized name, and is rebuilt on construction.
struct Snapshot: Sendable {
    var header: SnapshotHeader
    var nodes: [NodeRecord]
    private(set) var childrenIndex: [Int64: [Int64]]

    init(header: SnapshotHeader, nodes: [NodeRecord]) {
        self.header = header
        self.nodes = nodes
        var index: [Int64: [Int64]] = [:]
        for node in nodes {
            if let parent = node.parentID {
                index[parent, default: []].append(node.id)
            }
        }
        for key in index.keys {
            index[key]?.sort(by: { a, b in
                let first = nodes[Int(a)].name
                let second = nodes[Int(b)].name
                return first.localizedStandardCompare(second) == .orderedAscending
            })
        }
        self.childrenIndex = index
    }

    func node(_ id: Int64) -> NodeRecord? {
        guard id >= 0, id < Int64(nodes.count) else { return nil }
        return nodes[Int(id)]
    }

    func children(of id: Int64) -> [NodeRecord] {
        (childrenIndex[id] ?? []).compactMap { node($0) }
    }

    var root: NodeRecord? {
        nodes.first { $0.parentID == nil }
    }

    func absoluteURL(for node: NodeRecord, sourcePath: String) -> URL {
        if node.isDirectory && node.relativePath.isEmpty {
            return URL(fileURLWithPath: sourcePath)
        }
        return URL(fileURLWithPath: sourcePath).appending(path: node.relativePath)
    }

    /// All Finder tags present in the snapshot, ordered by frequency.
    var allTags: [String] {
        var counts: [String: Int] = [:]
        for node in nodes {
            for tag in node.tags ?? [] { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map(\.key)
    }

    /// Most common file extensions, ordered by count, capped for pickers.
    var topExtensions: [String] {
        var counts: [String: Int] = [:]
        for node in nodes where !node.isDirectory {
            if let ext = node.ext { counts[ext, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $0.key.lowercased()) > ($1.value, $1.key.lowercased()) }
            .prefix(60).map(\.key)
    }
}
