import Foundation

/// Kind of a scanned node. Symlinks are never followed during scanning.
enum NodeKind: String, Codable, Sendable, CaseIterable {
    case file
    case folder
    case symlink
    case package
}

/// Optional image metadata extracted with ImageIO (on demand).
struct ImageInfo: Codable, Sendable, Hashable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var format: String?
    var colorModel: String?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var iso: Int?
    var exposure: String?
    var fNumber: Double?
    var focalLength: Double?
    var orientation: Int?
    var takenDate: Date?
    var latitude: Double?
    var longitude: Double?
}

/// Optional audio/video metadata extracted with AVFoundation (on demand).
struct MediaInfo: Codable, Sendable, Hashable {
    var isVideo: Bool
    var durationSeconds: Double?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var codec: String?
    var bitrate: Int64?
    var sampleRate: Double?
    var channels: Int?
}

/// One node (file, folder, symlink or package) of a snapshot.
///
/// All "unknown" metadata is `nil` — it must be rendered as an unknown marker,
/// never as a zero value.
struct NodeRecord: Codable, Sendable, Hashable, Identifiable {
    var id: Int64
    var parentID: Int64?
    var name: String
    /// Slash-separated path relative to the scan root. Empty for the root node itself.
    var relativePath: String
    var ext: String?
    var isDirectory: Bool
    var isHidden: Bool
    var isSymlink: Bool
    var isPackage: Bool
    /// Logical size in bytes (nil when unknown, e.g. unreadable item).
    var size: Int64?
    /// Space actually occupied on disk (allocated size).
    var allocSize: Int64?
    var created: Date?
    var modified: Date?
    /// Finder tags.
    var tags: [String]?
    /// Direct children count (folders only; nil when unknown).
    var childCount: Int64?
    /// Recursive descendant count, excluding the folder itself (nil when unknown).
    var descendantCount: Int64?
    /// Recursive sum of logical file sizes inside the folder (nil when unknown).
    var dirSize: Int64?
    var sha256: String?
    var imageInfo: ImageInfo?
    var mediaInfo: MediaInfo?
    /// True when the file is an iCloud/cloud placeholder that is not downloaded locally.
    var notDownloaded: Bool
    /// Per-item error captured during scanning; the scan itself continues.
    var error: String?

    var kind: NodeKind {
        if isSymlink && !isDirectory { return .symlink }
        if isDirectory { return isPackage ? .package : .folder }
        return .file
    }

    var hasChildren: Bool { isDirectory }

    var displayName: String { name.isEmpty ? "/" : name }

    static func extensionOf(_ name: String) -> String? {
        guard !name.hasPrefix(".") else {
            let inner = name.dropFirst()
            guard let dot = inner.lastIndex(of: ".") else { return nil }
            return String(inner[inner.index(after: dot)...]).lowercased()
        }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : ext.lowercased()
    }
}

/// Lightweight row wrapper used by table/tree views. `children != nil` marks
/// folder rows for the outline (tree) table.
struct NodeRow: Identifiable, Hashable, Sendable {
    let record: NodeRecord
    var children: [NodeRow]?
    var id: Int64 { record.id }

    init(_ record: NodeRecord, children: [NodeRow]? = nil) {
        self.record = record
        self.children = children
    }
}
