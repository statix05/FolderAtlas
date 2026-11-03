import Foundation

/// Identifies what a map window should show: a saved snapshot or a new draft
/// scan for the given source path. Used with `WindowGroup(for:)` and `openWindow(value:)`.
struct MapWindowRequest: Codable, Hashable, Sendable {
    var snapshotID: UUID?
    var sourcePath: String?
    var suggestedName: String?

    static func existing(_ id: UUID) -> Self {
        MapWindowRequest(snapshotID: id, sourcePath: nil, suggestedName: nil)
    }

    static func draft(path: String, name: String?) -> Self {
        MapWindowRequest(snapshotID: nil, sourcePath: path, suggestedName: name)
    }
}
