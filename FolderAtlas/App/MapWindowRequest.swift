import Foundation

/// Identifies what a map window should show: a saved snapshot or a new draft
/// scan for the given source path. Used with `WindowGroup(for:)` and `openWindow(value:)`.
struct MapWindowRequest: Codable, Hashable, Sendable {
    var snapshotID: UUID?
    var sourcePath: String?
    var suggestedName: String?
    /// In-memory unsaved map registered in AppLibrary (lives until the app
    /// quits, survives window close — item 10).
    var draftID: UUID?

    static func existing(_ id: UUID) -> Self {
        MapWindowRequest(snapshotID: id, sourcePath: nil, suggestedName: nil, draftID: nil)
    }

    static func draft(path: String, name: String?) -> Self {
        MapWindowRequest(snapshotID: nil, sourcePath: path, suggestedName: name, draftID: nil)
    }

    static func existingDraft(_ id: UUID) -> Self {
        MapWindowRequest(snapshotID: nil, sourcePath: nil, suggestedName: nil, draftID: id)
    }
}
