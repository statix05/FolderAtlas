import Foundation
import SwiftUI
import AppKit
import os

enum EnrichmentScope: String, CaseIterable, Identifiable {
    case selection, filtered, all
    var id: String { rawValue }

    func ids(selection: Set<Int64>, filtered: [NodeRecord], all: [NodeRecord]) -> [Int64] {
        switch self {
        case .selection: return selection.sorted()
        case .filtered: return filtered.map(\.id)
        case .all: return all.map(\.id)
        }
    }
}

/// Per-window state: the map being viewed, scanning, filtering, saving,
/// enrichment and export. One instance per window.
@MainActor
@Observable
final class MapSession {

    static let log = Logger(subsystem: "sbs.statix.FolderAtlas", category: "session")

    enum Layout: String, CaseIterable, Identifiable {
        case list, tree
        var id: String { rawValue }
    }

    // Identity
    var request: MapWindowRequest?
    private(set) var isDraft = true
    var displayName: String = ""

    // Data
    private(set) var snapshot: Snapshot? {
        didSet {
            scheduleRebuild(tree: layout == .tree)
            selection.removeAll()
        }
    }

    var filter = FilterCriteria() {
        didSet {
            if oldValue != filter { scheduleRebuild(tree: false) }
        }
    }

    private(set) var filtered: [NodeRecord] = []
    /// Cached aggregates of the filtered set (updated by the row rebuild job).
    private(set) var filteredFiles = 0
    private(set) var filteredFolders = 0
    private(set) var filteredSize: Int64 = 0

    /// Rows shown by the list/table. Rebuilt OFF the main thread (filtering +
    /// mapping + sorting a huge map takes seconds), so the UI stays
    /// responsive and keeps showing the previous order until the new one is
    /// ready. See the 2026-11-04 perf work.
    private(set) var visibleRows: [NodeRow] = []

    /// Outline data for the tree layout; built together with rows on demand.
    private(set) var treeRows: [NodeRow]? = nil
    /// Guards against out-of-order row rebuilds.
    @ObservationIgnored private var rebuildGeneration = 0

    /// Folders and packages always sort before files.
    var foldersFirst: Bool {
        get { UserDefaults.standard.object(forKey: "sort.foldersFirst") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "sort.foldersFirst")
            scheduleRebuild(tree: layout == .tree)
        }
    }

    var selection: Set<Int64> = []

    var sortOrder: [ColumnSort] = NodeColumn.loadSort() {
        didSet {
            guard oldValue != sortOrder else { return }
            Self.log.info("sortOrder -> \(self.sortOrder.first?.column.rawValue ?? "-", privacy: .public)/\(self.sortOrder.first?.order == .reverse ? "R" : "F", privacy: .public)")
            NodeColumn.saveSort(sortOrder)
            scheduleRebuild(tree: layout == .tree)
        }
    }

    /// Native macOS table customization: column visibility, order and widths.
    /// Persisted as JSON in UserDefaults.
    /// Native column layout for the AppKit table (visibility + order + widths).
    /// Replaces the SwiftUI TableColumnCustomization, whose update path
    /// (AppKitOutlineTableCoordinator) prepared a hosting view per inserted
    /// row and hung the app on million-row maps.
    struct ColumnLayout: Codable, Equatable {
        var visible: [NodeColumn]
        var widths: [String: Double]

        static let `default` = ColumnLayout(
            visible: [.name, .kind, .ext, .size, .modified, .path],
            widths: [:])

        static func load() -> ColumnLayout {
            guard let data = UserDefaults.standard.data(forKey: "columns.layout"),
                  let decoded = try? JSONDecoder().decode(ColumnLayout.self, from: data) else {
                return .default
            }
            return decoded
        }

        func save() {
            if let data = try? JSONEncoder().encode(self) {
                UserDefaults.standard.set(data, forKey: "columns.layout")
            }
        }
    }

    var columnLayout: ColumnLayout = ColumnLayout.load() {
        didSet {
            guard oldValue != columnLayout else { return }
            columnLayout.save()
            displayRevision += 1
        }
    }

    /// Bumped whenever the displayed data or column configuration changes so
    /// the AppKit table knows to reload. OBSERVED on purpose — it is the
    /// primary signal that drives NSViewRepresentable.updateNSView.
    private(set) var displayRevision = 0

    var layout: Layout = .list {
        didSet {
            if oldValue != layout, layout == .tree, treeRows == nil {
                scheduleRebuild(tree: true)
            }
        }
    }
    var inspectorVisible = true

    // Scan state
    private(set) var isScanning = false
    private(set) var progress = ScanProgress()
    var scanError: String?
    var notice: String?
    private(set) var sourceAvailable: Bool?

    // Enrichment
    private(set) var isEnriching = false
    private(set) var enrichmentProgress: (done: Int, total: Int)?

    private var scanTask: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?

    // MARK: - Requests & loading

    func apply(request: MapWindowRequest) {
        guard self.request != request else { return }
        self.request = request
        if let id = request.snapshotID {
            isDraft = false
            Task { await loadSnapshot(id: id) }
        } else if let path = request.sourcePath {
            isDraft = true
            displayName = URL(fileURLWithPath: path).lastPathComponent
            Task { await startScan(at: URL(fileURLWithPath: path)) }
        }
    }

    func loadSnapshot(id: UUID) async {
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try SnapshotStore.load(id: id)
            }.value
            self.snapshot = snapshot
            displayName = snapshot.header.displayName
            filter = FilterCriteria()
            checkSourceAvailability()
        } catch {
            scanError = error.localizedDescription
        }
    }

    // MARK: - Scanning

    func startScan(at url: URL) async {
        guard !isScanning else { return }
        let defaults = UserDefaults.standard
        let config = ScanConfiguration(
            includeHidden: defaults.object(forKey: "scan.includeHidden") as? Bool ?? true,
            includePackageContents: defaults.object(forKey: "scan.includePackages") as? Bool ?? true,
            computeFolderSizes: defaults.object(forKey: "scan.computeFolderSizes") as? Bool ?? true,
            maxDepth: nil)

        isScanning = true
        scanError = nil
        progress = ScanProgress()
        if request == nil { request = MapWindowRequest.draft(path: url.path, name: nil) }
        displayName = displayName.isEmpty ? url.lastPathComponent : displayName

        scanTask = Task {
            do {
                let output = try await ScanEngine.run(root: url, config: config) { [weak self] event in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self.progress = event
                        }
                    }
                }
                await adopt(output: output, url: url, config: config)
            } catch is CancellationError {
                await adopt(cancelledAt: url, config: config)
            } catch {
                scanError = error.localizedDescription
            }
            isScanning = false
        }
    }

    func rescan() async {
        guard let source = snapshot?.header.sourcePath ?? request?.sourcePath else { return }
        isDraft = true
        await startScan(at: URL(fileURLWithPath: source))
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func adopt(output: ScanOutput, url: URL, config: ScanConfiguration) async {
        let name = displayName.isEmpty ? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) : displayName
        let header = SnapshotHeader(
            displayName: name,
            sourcePath: url.path,
            scanSettings: config,
            fileCount: output.stats.fileCount,
            folderCount: output.stats.folderCount,
            errorCount: output.stats.errorCount,
            totalSize: output.stats.totalSize,
            durationSeconds: output.stats.durationSeconds)
        snapshot = Snapshot(header: header, nodes: output.nodes)
        if output.cancelled {
            notice = String(localized: "Scan cancelled — the map is incomplete.")
        }
        checkSourceAvailability()
    }

    private func adopt(cancelledAt url: URL, config: ScanConfiguration) async {
        // The engine finalizes partial results even on cancellation; nothing
        // else to do here — the cancelled run may already have been adopted.
        notice = String(localized: "Scan cancelled — the map is incomplete.")
    }

    func checkSourceAvailability() {
        guard let source = snapshot?.header.sourcePath ?? request?.sourcePath else { return }
        let path = source
        Task.detached(priority: .utility) { [weak self] in
            let exists = FileManager.default.fileExists(atPath: path)
            await MainActor.run {
                MainActor.assumeIsolated {
                    self?.sourceAvailable = exists
                }
            }
        }
    }

    // MARK: - Filtering & derived data (off-main-thread)

    /// Schedules an async rebuild of filtered rows/aggregates (and optionally
    /// the outline tree). Results are applied on the main actor only if this
    /// generation is still current — rapid sort/filter changes never race.
    private func scheduleRebuild(tree: Bool) {
        rebuildGeneration += 1
        let generation = rebuildGeneration
        guard let snapshot else {
            visibleRows = []
            treeRows = nil
            filtered = []
            filteredFiles = 0
            filteredFolders = 0
            filteredSize = 0
            return
        }
        let filter = filter
        let sortOrder = sortOrder
        let foldersFirst = foldersFirst
        let needsTree = tree || (layout == .tree && treeRows == nil)
        Task.detached(priority: .userInitiated) { [weak self] in
            let filtered = filter.isEmpty ? snapshot.nodes : snapshot.nodes.filter { filter.matches($0) }
            var files = 0
            var folders = 0
            var size: Int64 = 0
            for node in filtered {
                if node.isDirectory {
                    folders += 1
                } else {
                    files += 1
                    if let nodeSize = node.size { size += nodeSize }
                }
            }
            let rows = RowSorting.apply(filtered.map { NodeRow($0) },
                                        sortOrder: sortOrder,
                                        foldersFirst: foldersFirst)
            let tree: [NodeRow]? = needsTree ? Self.buildTreeRows(from: snapshot,
                                                                  sortOrder: sortOrder,
                                                                  foldersFirst: foldersFirst) : nil
            await MainActor.run {
                guard let self, generation == self.rebuildGeneration else { return }
                self.filtered = filtered
                self.filteredFiles = files
                self.filteredFolders = folders
                self.filteredSize = size
                self.visibleRows = rows
                if needsTree { self.treeRows = tree }
                self.displayRevision += 1
                Self.log.info("apply gen=\(generation) rows=\(rows.count) first=\(rows.first?.record.displayName ?? "-", privacy: .public) rev=\(self.displayRevision) tree=\(needsTree)")
            }
        }
    }

    nonisolated private static func buildTreeRows(from snapshot: Snapshot,
                                      sortOrder: [ColumnSort],
                                      foldersFirst: Bool) -> [NodeRow] {
        func makeRow(_ record: NodeRecord) -> NodeRow {
            let kids = snapshot.children(of: record.id)
            if kids.isEmpty {
                return NodeRow(record)
            }
            let childRows = RowSorting.apply(kids.map { NodeRow($0) },
                                             sortOrder: sortOrder,
                                             foldersFirst: foldersFirst)
                .map { row -> NodeRow in makeRow(row.record) }
            return NodeRow(record, children: childRows)
        }
        guard let root = snapshot.root else { return [] }
        return [makeRow(root)]
    }

    var selectedNodes: [NodeRecord] {
        guard let snapshot else { return [] }
        return selection.compactMap { snapshot.node($0) }.sorted { $0.id < $1.id }
    }

    var singleSelectedNode: NodeRecord? {
        selection.count == 1 ? selectedNodes.first : nil
    }

    // MARK: - Saving

    func saveSnapshot(as name: String) {
        guard var snapshot else { return }
        snapshot.header.displayName = name
        do {
            try SnapshotStore.save(snapshot)
            self.snapshot = snapshot
            displayName = name
            isDraft = false
            AppLibrary.shared.reload()
            notice = String(localized: "Map saved.")
        } catch {
            scanError = error.localizedDescription
        }
    }

    // MARK: - Enrichment

    func computeChecksums(scope: EnrichmentScope) {
        guard let snapshot, !isEnriching else { return }
        let ids = scope.ids(selection: selection, filtered: filtered, all: snapshot.nodes)
        guard !ids.isEmpty else { return }
        let sourceRoot = URL(fileURLWithPath: snapshot.header.sourcePath)
        let nodes = snapshot.nodes
        isEnriching = true
        enrichmentProgress = (0, ids.count)
        enrichTask = Task {
            let results = await EnrichmentService.checksums(for: ids, nodes: nodes, sourceRoot: sourceRoot) { [weak self] done, total in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.enrichmentProgress = (done, total)
                    }
                }
            }
            if !Task.isCancelled {
                await applyChecksums(results)
            }
            isEnriching = false
            enrichmentProgress = nil
        }
    }

    func extractMediaMetadata(scope: EnrichmentScope) {
        guard let snapshot, !isEnriching else { return }
        let ids = scope.ids(selection: selection, filtered: filtered, all: snapshot.nodes)
        guard !ids.isEmpty else { return }
        let sourceRoot = URL(fileURLWithPath: snapshot.header.sourcePath)
        let nodes = snapshot.nodes
        isEnriching = true
        enrichmentProgress = (0, ids.count)
        enrichTask = Task {
            let results = await EnrichmentService.media(for: ids, nodes: nodes, sourceRoot: sourceRoot) { [weak self] done, total in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.enrichmentProgress = (done, total)
                    }
                }
            }
            if !Task.isCancelled {
                await applyMedia(results)
            }
            isEnriching = false
            enrichmentProgress = nil
        }
    }

    func cancelEnrichment() {
        enrichTask?.cancel()
    }

    private func applyChecksums(_ results: [Int64: String]) async {
        guard var nodes = snapshot?.nodes else { return }
        for (id, hex) in results where id >= 0 && id < Int64(nodes.count) {
            nodes[Int(id)].sha256 = hex
        }
        snapshot?.nodes = nodes
    }

    private func applyMedia(_ results: [Int64: EnrichmentService.MediaOutcome]) async {
        guard var nodes = snapshot?.nodes else { return }
        for (id, outcome) in results where id >= 0 && id < Int64(nodes.count) {
            nodes[Int(id)].imageInfo = outcome.imageInfo
            nodes[Int(id)].mediaInfo = outcome.mediaInfo
            if let error = outcome.error { nodes[Int(id)].error = error }
        }
        snapshot?.nodes = nodes
    }

    // MARK: - Compare & duplicates

    func compare(oldID: UUID, newID: UUID) async {
        do {
            let first = try await Task.detached(priority: .userInitiated) {
                try SnapshotStore.load(id: oldID)
            }.value
            let second = try await Task.detached(priority: .userInitiated) {
                try SnapshotStore.load(id: newID)
            }.value
            let older = first.header.createdAt <= second.header.createdAt ? first : second
            let newer = first.header.createdAt <= second.header.createdAt ? second : first
            let report = await Task.detached(priority: .userInitiated) {
                SnapshotDiff.compare(old: older, new: newer)
            }.value
            diffReport = report
        } catch {
            scanError = error.localizedDescription
        }
    }

    var diffReport: DiffReport?
    var showDiff = false
    var duplicatesReport: DuplicateFinder.Report?
    var showDuplicates = false

    func findDuplicates() async {
        guard let snapshot else { return }
        let sourceRoot = URL(fileURLWithPath: snapshot.header.sourcePath)
        let nodes = snapshot.nodes
        isEnriching = true
        let report = await DuplicateFinder.find(in: nodes, sourceRoot: sourceRoot)
        isEnriching = false
        duplicatesReport = report
        showDuplicates = true
    }

    // MARK: - Row actions

    func absoluteURL(of node: NodeRecord) -> URL {
        guard let source = snapshot?.header.sourcePath ?? request?.sourcePath else {
            return URL(fileURLWithPath: node.relativePath)
        }
        if node.relativePath.isEmpty {
            return URL(fileURLWithPath: source)
        }
        return URL(fileURLWithPath: source).appending(path: node.relativePath)
    }

    func open(_ node: NodeRecord) {
        NSWorkspace.shared.open(absoluteURL(of: node))
    }

    func reveal(_ node: NodeRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([absoluteURL(of: node)])
    }

    func copyPath(_ node: NodeRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(absoluteURL(of: node).path, forType: .string)
    }

    func copyPaths(_ nodes: [NodeRecord]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(nodes.map { absoluteURL(of: $0).path }.joined(separator: "\n"), forType: .string)
    }

    func quickLookSelection() {
        let nodes = selectedNodes.isEmpty ? filtered : selectedNodes
        let urls = nodes.filter { !$0.isDirectory }.map { absoluteURL(of: $0) }
        QuickLookCenter.shared.show(urls: Array(urls.prefix(50)))
    }
}
