import Foundation
import AppKit

/// Cross-window application state: the index of saved maps and incoming
/// folder requests from Finder Services, dock drops and "Open With".
@MainActor
@Observable
final class AppLibrary {
    static let shared = AppLibrary()

    static let folderRequestNotification = Notification.Name("AppLibrary.folderRequest")

    private(set) var savedMaps: [SnapshotHeader] = []
    private(set) var rejectedCount = 0

    /// True while Finder-service exports are running. Set before the SwiftUI
    /// scenes appear so a cold service launch can hide its window and quit
    /// when the exports finish.
    private(set) var serviceMode = false
    private var serviceWorkPending = 0

    /// Whether service-triggered exports are still running.
    var serviceWorkRunning: Bool { serviceWorkPending > 0 }

    private var pendingURLs: [URL] = []

    private init() {
        reload()
    }

    func reload() {
        savedMaps = SnapshotStore.list()
    }

    /// Called by the services provider when work starts.
    func beginServiceWork(folderCount: Int) {
        serviceMode = true
        serviceWorkPending += folderCount
    }

    /// Called when all service exports finished. If the app was launched by
    /// the service, hide and terminate; a normally-running instance stays open.
    func endServiceWork() {
        serviceWorkPending = max(0, serviceWorkPending - 1)
        guard serviceWorkPending == 0, serviceMode else { return }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }

    /// Normal (non-service) launch: cancel the terminate-on-idle behaviour.
    func cancelServiceMode() {
        serviceMode = false
        serviceWorkPending = 0
    }

    /// Takes (and clears) all pending folder requests. First caller wins;
    /// additional windows receive an empty array.
    func takePendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }

    // MARK: - Unsaved maps (in-memory drafts; live until the app quits)

    /// An unsaved map. Held in memory only — closing windows or switching to
    /// a saved map does NOT discard it; quitting the app does (owner request).
    @Observable
    final class DraftMap: Identifiable {
        let id = UUID()
        var displayName: String
        var sourcePath: String
        var snapshot: Snapshot?

        init(displayName: String, sourcePath: String) {
            self.displayName = displayName
            self.sourcePath = sourcePath
        }
    }

    private(set) var drafts: [DraftMap] = []

    /// Registers (or reuses, by source path) an unsaved map.
    @discardableResult
    func openDraft(sourcePath: String, name: String) -> DraftMap {
        if let existing = drafts.first(where: { $0.sourcePath == sourcePath }) {
            return existing
        }
        let draft = DraftMap(
            displayName: name.isEmpty ? URL(fileURLWithPath: sourcePath).lastPathComponent : name,
            sourcePath: sourcePath)
        drafts.insert(draft, at: 0)
        return draft
    }

    func updateDraft(id: UUID, displayName: String, snapshot: Snapshot?) {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[index].displayName = displayName
        drafts[index].snapshot = snapshot
    }

    func discardDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
    }

    func draft(id: UUID) -> DraftMap? {
        drafts.first { $0.id == id }
    }

    /// Accepts folder URLs from Finder Services / dock drops / open events.
    /// Non-folders are counted as rejected and ignored.
    func submit(urls: [URL]) {
        let folders = urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        if folders.count != urls.count {
            rejectedCount += urls.count - folders.count
        }
        guard !folders.isEmpty else { return }
        pendingURLs.append(contentsOf: folders)
        NotificationCenter.default.post(name: Self.folderRequestNotification, object: nil)
    }

    func delete(id: UUID) {
        try? SnapshotStore.delete(id: id)
        reload()
    }

    func rename(id: UUID, to name: String) {
        try? SnapshotStore.rename(id: id, to: name)
        reload()
    }

    /// Groups saved maps by source path — the "history" of each source.
    func historyGroups() -> [(source: String, maps: [SnapshotHeader])] {
        var groups: [String: [SnapshotHeader]] = [:]
        for map in savedMaps { groups[map.sourcePath, default: []].append(map) }
        return groups
            .map { (key, maps) in (source: key, maps: maps.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { a, b in a.source.localizedStandardCompare(b.source) == .orderedAscending }
    }
}
