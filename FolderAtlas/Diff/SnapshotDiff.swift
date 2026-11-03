import Foundation

enum DiffKind: String, Sendable, CaseIterable {
    case added, removed, changed, moved
}

enum MoveConfidence: String, Sendable {
    case high, medium
}

struct DiffEntry: Identifiable, Sendable, Hashable {
    var id: String
    var kind: DiffKind
    /// Node in the newer snapshot (nil for removed items).
    var current: NodeRecord?
    /// Node in the older snapshot (nil for added items).
    var previous: NodeRecord?
    /// For moved/renamed items: the path in the other snapshot.
    var movedFrom: String?
    var confidence: MoveConfidence?
    var sizeDelta: Int64?

    var path: String { current?.relativePath ?? previous?.relativePath ?? id }
    var name: String { current?.name ?? previous?.name ?? id }
}

struct DiffReport: Sendable {
    var added: [DiffEntry] = []
    var removed: [DiffEntry] = []
    var changed: [DiffEntry] = []
    var moved: [DiffEntry] = []
    var hasChecksums = false

    var total: Int { added.count + removed.count + changed.count + moved.count }
    var isEmpty: Bool { total == 0 }
}

/// Compares two snapshots of the same source by relative path.
///
/// Change criteria: same path but different size, modified date, or checksum
/// (when both snapshots carry checksums).
/// Move detection is a HEURISTIC and clearly labelled as such: candidates are
/// paired by equal size, then by equal checksum (high confidence) or equal
/// creation date + extension (medium confidence), tie-broken by name similarity.
enum SnapshotDiff {

    static func compare(old: Snapshot, new: Snapshot) -> DiffReport {
        var report = DiffReport()
        let oldByID = Dictionary(old.nodes.map { ($0.relativePath, $0) }, uniquingKeysWith: { a, _ in a })
        let newByID = Dictionary(new.nodes.map { ($0.relativePath, $0) }, uniquingKeysWith: { a, _ in a })
        report.hasChecksums = old.nodes.contains { $0.sha256 != nil } && new.nodes.contains { $0.sha256 != nil }

        var removedOld: [String: NodeRecord] = [:]
        var addedNew: [String: NodeRecord] = [:]

        for (path, oldNode) in oldByID {
            if let newNode = newByID[path] {
                if isChanged(oldNode, newNode) {
                    report.changed.append(DiffEntry(
                        id: path, kind: .changed, current: newNode, previous: oldNode,
                        sizeDelta: delta(newNode.size, oldNode.size)))
                }
            } else {
                removedOld[path] = oldNode
            }
        }
        for (path, newNode) in newByID where oldByID[path] == nil {
            addedNew[path] = newNode
        }

        let moves = detectMoves(removed: removedOld, added: addedNew)
        for move in moves { report.moved.append(move) }
        let consumedRemoved = Set(moves.compactMap(\.movedFrom))
        let consumedAdded = Set(moves.compactMap { $0.current?.relativePath })
        for (path, node) in removedOld where !consumedRemoved.contains(path) {
            report.removed.append(DiffEntry(id: path, kind: .removed, current: nil, previous: node))
        }
        for (path, node) in addedNew where !consumedAdded.contains(path) {
            report.added.append(DiffEntry(id: path, kind: .added, current: node, previous: nil))
        }
        report.changed.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        report.added.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        report.removed.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        report.moved.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return report
    }

    private static func isChanged(_ old: NodeRecord, _ new: NodeRecord) -> Bool {
        if old.size != new.size { return true }
        if old.modified != new.modified { return true }
        if let oldHash = old.sha256, let newHash = new.sha256, oldHash != newHash { return true }
        return false
    }

    private static func delta(_ new: Int64?, _ old: Int64?) -> Int64? {
        guard let new, let old else { return nil }
        return new - old
    }

    private static func detectMoves(removed: [String: NodeRecord],
                                    added: [String: NodeRecord]) -> [DiffEntry] {
        var removedBySize: [Int64: [(String, NodeRecord)]] = [:]
        var addedBySize: [Int64: [(String, NodeRecord)]] = [:]
        for (path, node) in removed where node.size != nil { removedBySize[node.size!, default: []].append((path, node)) }
        for (path, node) in added where node.size != nil { addedBySize[node.size!, default: []].append((path, node)) }

        var usedAdded: Set<String> = []
        var moves: [DiffEntry] = []

        for (size, removedList) in removedBySize {
            guard let addedList = addedBySize[size] else { continue }
            for (oldPath, oldNode) in removedList {
                var best: (path: String, node: NodeRecord, confidence: MoveConfidence, similarity: Double)?
                for (newPath, newNode) in addedList where !usedAdded.contains(newPath) {
                    let confidence: MoveConfidence?
                    if let oldHash = oldNode.sha256, let newHash = newNode.sha256 {
                        confidence = oldHash == newHash ? .high : nil
                    } else {
                        confidence = nil
                    }
                    let dateMatch = oldNode.created != nil
                        && oldNode.created == newNode.created
                        && oldNode.ext == newNode.ext
                    let strength: MoveConfidence? = confidence ?? (dateMatch ? .medium : nil)
                    guard let strength else { continue }
                    let similarity = nameSimilarity(oldNode.name, newNode.name)
                    if best == nil || similarity > best!.similarity {
                        best = (newPath, newNode, strength, similarity)
                    }
                }
                if let best {
                    usedAdded.insert(best.path)
                    moves.append(DiffEntry(
                        id: oldPath, kind: .moved, current: best.node, previous: oldNode,
                        movedFrom: oldPath, confidence: best.confidence,
                        sizeDelta: 0))
                }
            }
        }
        return moves
    }

    /// Dice coefficient over character bigrams; 0...1.
    static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let lhs = a.lowercased()
        let rhs = b.lowercased()
        guard lhs.count > 1, rhs.count > 1 else { return lhs == rhs ? 1 : 0 }
        func bigrams(_ s: String) -> [String] {
            let chars = Array(s)
            return (0..<(chars.count - 1)).map { String(chars[$0...$0 + 1]) }
        }
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        var rightCounts: [String: Int] = [:]
        for gram in right { rightCounts[gram, default: 0] += 1 }
        var intersection = 0
        for gram in left {
            if let count = rightCounts[gram], count > 0 {
                intersection += 1
                rightCounts[gram] = count - 1
            }
        }
        return Double(2 * intersection) / Double(left.count + right.count)
    }
}
