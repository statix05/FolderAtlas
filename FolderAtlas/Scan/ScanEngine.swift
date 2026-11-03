import Foundation
import Darwin

/// Live progress of a scan. Reported from worker tasks to the UI.
struct ScanProgress: Sendable, Equatable {
    var files: Int = 0
    var folders: Int = 0
    var errors: Int = 0
    var bytesProcessed: Int64 = 0
    var currentPath: String = ""
    var finished: Bool = false
    var cancelled: Bool = false
}

struct ScanStats: Sendable {
    var fileCount: Int = 0
    var folderCount: Int = 0
    var errorCount: Int = 0
    var totalSize: Int64 = 0
    var durationSeconds: Double = 0
    var rootPath: String = ""
}

struct ScanOutput: Sendable {
    var nodes: [NodeRecord]
    var stats: ScanStats
    var cancelled: Bool
}

enum ScanError: LocalizedError, Sendable {
    case rootUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .rootUnreadable(let path):
            return String(localized: "The folder could not be read: \(path)")
        }
    }
}

/// Parallel recursive scanner.
///
/// - Bounded concurrency: a fixed pool of workers pulls directories from a shared queue.
/// - Symlinks are never followed for recursion (a cycle through links is impossible);
///   an inode set additionally guards exotic filesystems against double visits.
/// - Errors on individual items are recorded on the item and never abort the scan.
/// - iCloud placeholders are recorded but never downloaded.
/// - Original files are never modified.
///
/// Folder aggregates (child count, recursive descendant count, recursive size) are
/// stored per directory during its own enumeration (direct values only) and folded
/// bottom-up at the end — parents always have smaller ids than their children, so a
/// single descending pass is enough and no merge ordering race can occur.
enum ScanEngine {

    private struct ScanJob: Sendable {
        var url: URL
        var id: Int64
        var parentID: Int64?
        /// Relative path of the parent directory ("" for the root).
        var parentRelative: String
        var depth: Int
    }

    private struct InodeKey: Hashable, Sendable {
        var dev: UInt64
        var ino: UInt64
    }

    private actor State {
        private var records: [Int64: NodeRecord] = [:]
        private var nextID: Int64 = 0
        private var pending: [ScanJob] = []
        private var pendingIndex = 0
        private var active = 0
        private var visited: Set<InodeKey> = []
        private var lastReport = Date.distantPast
        private(set) var fileCount = 0
        private(set) var folderCount = 0
        private(set) var errorCount = 0
        private(set) var totalSize: Int64 = 0

        enum Claim: Sendable { case job(ScanJob); case wait; case done }

        func claim() -> Claim {
            if pendingIndex < pending.count {
                active += 1
                let job = pending[pendingIndex]
                pendingIndex += 1
                return .job(job)
            }
            return active == 0 ? .done : .wait
        }

        func release() { active -= 1 }

        func reserveIDs(_ n: Int) -> Int64 {
            let base = nextID
            nextID += Int64(n)
            return base
        }

        func add(_ batch: [NodeRecord]) {
            for record in batch { records[record.id] = record }
        }

        func countFile(size: Int64?) {
            fileCount += 1
            if let size { totalSize += size }
        }

        func countFolder() {
            folderCount += 1
        }

        func recordError() {
            errorCount += 1
        }

        /// Stores the direct (non-recursive) statistics of a directory right after
        /// its own enumeration finished.
        func setDirectoryStats(_ id: Int64, childCount: Int64, directSize: Int64, computeSizes: Bool) {
            guard var record = records[id] else { return }
            record.childCount = childCount
            if computeSizes { record.dirSize = directSize }
            records[id] = record
        }

        func push(_ job: ScanJob) { pending.append(job) }

        /// Records an unrecoverable error on a directory record itself.
        func failDirectory(_ job: ScanJob, message: String) {
            if var record = records[job.id] {
                record.error = message
                records[job.id] = record
            }
            errorCount += 1
        }

        /// Registers an inode; returns false when it was already visited (cycle guard).
        func visit(_ key: InodeKey) -> Bool { visited.insert(key).inserted }

        /// Throttled progress snapshot; returns nil when reporting too frequently.
        func reportProgress(currentPath: String) -> ScanProgress? {
            let now = Date()
            guard now.timeIntervalSince(lastReport) > 0.15 else { return nil }
            lastReport = now
            return ScanProgress(files: fileCount, folders: folderCount, errors: errorCount,
                                bytesProcessed: totalSize, currentPath: currentPath)
        }

        func stats(rootPath: String) -> ScanStats {
            ScanStats(fileCount: fileCount, folderCount: folderCount, errorCount: errorCount,
                      totalSize: totalSize, durationSeconds: 0, rootPath: rootPath)
        }

        /// Bottom-up fold of folder aggregates, then renumbering into dense ids.
        func finalize() -> [NodeRecord] {
            var ordered = records.values.sorted { $0.id < $1.id }
            var byID: [Int64: NodeRecord] = [:]
            var childrenOf: [Int64: [Int64]] = [:]
            for record in ordered {
                byID[record.id] = record
                if let parent = record.parentID {
                    childrenOf[parent, default: []].append(record.id)
                }
            }
            // Parents are always created before children, so ids grow with depth.
            for index in stride(from: ordered.count - 1, through: 0, by: -1) {
                var record = ordered[index]
                guard record.isDirectory, let kids = childrenOf[record.id] else { continue }
                var sizeSum = record.dirSize ?? 0
                var descendantSum = record.childCount ?? 0
                var anySizeKnown = record.dirSize != nil
                for kid in kids {
                    guard let child = byID[kid] else { continue }
                    if let childSize = child.dirSize { sizeSum += childSize; anySizeKnown = true }
                    if let childDescendants = child.descendantCount { descendantSum += childDescendants }
                }
                if anySizeKnown { record.dirSize = sizeSum }
                if record.childCount != nil { record.descendantCount = descendantSum }
                ordered[index] = record
                byID[record.id] = record
            }

            var map: [Int64: Int64] = [:]
            for (index, record) in ordered.enumerated() { map[record.id] = Int64(index) }
            return ordered.map { record in
                var remapped = record
                remapped.id = map[record.id] ?? 0
                remapped.parentID = record.parentID.flatMap { map[$0] }
                return remapped
            }
        }
    }

    static func run(root: URL,
                    config: ScanConfiguration,
                    onProgress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> ScanOutput {
        let started = Date()
        let state = State()

        var rootInfo = Stat.lstat(root.path)
        if rootInfo == nil {
            rootInfo = Stat.lstat(root.resolvingSymlinksInPath().path)
        }
        guard let rootStat = rootInfo else { throw ScanError.rootUnreadable(root.path) }

        let rootID = await state.reserveIDs(1)
        let rootRecord = NodeRecord(
            id: rootID, parentID: nil,
            name: root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent,
            relativePath: "", ext: nil,
            isDirectory: true, isHidden: false, isSymlink: false, isPackage: false,
            size: rootStat.size, allocSize: rootStat.allocSize,
            created: rootStat.created, modified: rootStat.modified,
            tags: (try? root.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? nil,
            notDownloaded: false)
        await state.add([rootRecord])
        await state.countFolder()
        _ = await state.visit(InodeKey(dev: rootStat.dev, ino: rootStat.ino))
        await state.push(ScanJob(url: root, id: rootID, parentID: nil, parentRelative: "", depth: 0))

        let workerCount = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
        var cancelled = false
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<workerCount {
                    group.addTask {
                        try await processLoop(state: state, config: config, onProgress: onProgress)
                    }
                }
                try await group.waitForAll()
            }
        } catch is CancellationError {
            cancelled = true
        }
        let nodes = await state.finalize()
        var stats = await state.stats(rootPath: root.path)
        stats.durationSeconds = Date().timeIntervalSince(started)
        onProgress?(ScanProgress(files: stats.fileCount, folders: stats.folderCount,
                                 errors: stats.errorCount, bytesProcessed: stats.totalSize,
                                 currentPath: "", finished: true, cancelled: cancelled))
        return ScanOutput(nodes: nodes, stats: stats, cancelled: cancelled)
    }

    private static func processLoop(state: State,
                                    config: ScanConfiguration,
                                    onProgress: (@Sendable (ScanProgress) -> Void)?) async throws {
        while true {
            if Task.isCancelled { throw CancellationError() }
            switch await state.claim() {
            case .done:
                return
            case .wait:
                try await Task.sleep(for: .milliseconds(5))
            case .job(let job):
                do {
                    try await process(job, state: state, config: config, onProgress: onProgress)
                } catch is CancellationError {
                    await state.release()
                    throw CancellationError()
                } catch {
                    await state.failDirectory(job, message: error.localizedDescription)
                }
                await state.release()
                if let onProgress, let snapshot = await state.reportProgress(currentPath: job.url.path) {
                    onProgress(snapshot)
                }
            }
        }
    }

    private static func process(_ job: ScanJob,
                                state: State,
                                config: ScanConfiguration,
                                onProgress: (@Sendable (ScanProgress) -> Void)?) async throws {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .isPackageKey,
                                      .isHiddenKey, .tagNamesKey, .isUbiquitousItemKey,
                                      .ubiquitousItemDownloadingStatusKey]
        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(at: job.url,
                                                  includingPropertiesForKeys: keys,
                                                  options: config.includeHidden ? [] : [.skipsHiddenFiles])
        } catch {
            await state.failDirectory(job, message: error.localizedDescription)
            return
        }

        let base = await state.reserveIDs(children.count)
        var batch: [NodeRecord] = []
        var newJobs: [ScanJob] = []
        var itemsSeen = 0
        var directSize: Int64 = 0

        for (index, url) in children.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            itemsSeen += 1
            if onProgress != nil && itemsSeen >= 1024 {
                if let snapshot = await state.reportProgress(currentPath: url.path) {
                    onProgress?(snapshot)
                }
                itemsSeen = 0
            }

            let id = base + Int64(index)
            let record = buildRecord(url: url, id: id, parentID: job.id,
                                     parentRelative: job.parentRelative)
            batch.append(record)

            if record.error != nil {
                await state.recordError()
                continue
            }

            if record.isDirectory {
                await state.countFolder()
                let mayDescend = (!record.isPackage || config.includePackageContents)
                    && (config.maxDepth == nil || job.depth + 1 <= config.maxDepth!)
                if mayDescend, let stat = Stat.lstat(url.path) {
                    let key = InodeKey(dev: stat.dev, ino: stat.ino)
                    if await state.visit(key) {
                        newJobs.append(ScanJob(url: url, id: id, parentID: job.id,
                                               parentRelative: record.relativePath, depth: job.depth + 1))
                    }
                }
            } else {
                if let size = record.size { directSize += size }
                await state.countFile(size: record.size)
            }
        }

        await state.add(batch)
        for newJob in newJobs { await state.push(newJob) }
        await state.setDirectoryStats(job.id, childCount: Int64(children.count),
                                      directSize: directSize,
                                      computeSizes: config.computeFolderSizes)
    }

    private static func buildRecord(url: URL, id: Int64, parentID: Int64?, parentRelative: String) -> NodeRecord {
        var isDir = false
        var isSym = false
        var isHidden = false
        var isPackage = false
        var tags: [String]?
        var notDownloaded = false

        if let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isPackageKey,
                                                     .isHiddenKey, .tagNamesKey, .isUbiquitousItemKey,
                                                     .ubiquitousItemDownloadingStatusKey]) {
            isSym = rv.isSymbolicLink ?? false
            isDir = (rv.isDirectory ?? false) && !isSym
            isHidden = rv.isHidden ?? false
            isPackage = isDir && (rv.isPackage ?? false)
            tags = rv.tagNames
            if rv.isUbiquitousItem == true,
               let status = rv.ubiquitousItemDownloadingStatus,
               status != .current {
                notDownloaded = true
            }
        }

        let name = url.lastPathComponent
        let relativePath = parentRelative.isEmpty ? name : parentRelative + "/" + name

        var size: Int64?
        var allocSize: Int64?
        var created: Date?
        var modified: Date?
        var error: String?

        if let stat = Stat.lstat(url.path) {
            size = stat.size
            allocSize = stat.allocSize
            created = stat.created
            modified = stat.modified
        } else {
            error = String(localized: "The item could not be inspected")
        }

        return NodeRecord(
            id: id,
            parentID: parentID,
            name: name,
            relativePath: relativePath,
            ext: isDir ? nil : NodeRecord.extensionOf(name),
            isDirectory: isDir,
            isHidden: isHidden,
            isSymlink: isSym,
            isPackage: isPackage,
            size: size,
            allocSize: allocSize,
            created: created,
            modified: modified,
            tags: tags,
            notDownloaded: notDownloaded,
            error: error)
    }
}

/// Thin wrapper around Darwin `lstat` — never follows symlinks.
enum Stat {
    struct Info: Sendable {
        var size: Int64
        var allocSize: Int64
        var created: Date?
        var modified: Date?
        var dev: UInt64
        var ino: UInt64
    }

    static func lstat(_ path: String) -> Info? {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { return nil }
        let created = Date(timeIntervalSince1970:
            TimeInterval(st.st_birthtimespec.tv_sec) + TimeInterval(st.st_birthtimespec.tv_nsec) / 1_000_000_000)
        let modified = Date(timeIntervalSince1970:
            TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000)
        return Info(
            size: Int64(st.st_size),
            allocSize: Int64(st.st_blocks) * 512,
            created: created,
            modified: modified,
            dev: UInt64(st.st_dev),
            ino: st.st_ino)
    }
}
