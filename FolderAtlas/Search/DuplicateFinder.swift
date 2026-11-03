import Foundation

/// A group of files with identical content (same SHA-256 and size).
struct DuplicateGroup: Identifiable, Sendable {
    var hash: String
    var size: Int64
    var nodes: [NodeRecord]

    var id: String { hash }
}

/// Content duplicate detection: group by size first, hash only the candidates.
/// Equal names alone are never treated as duplicates.
enum DuplicateFinder {

    struct Report: Sendable {
        var groups: [DuplicateGroup]
        var hashedCount: Int
        var candidateCount: Int
        var cancelled: Bool
    }

    static func find(in nodes: [NodeRecord],
                     sourceRoot: URL,
                     onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> Report {
        var bySize: [Int64: [NodeRecord]] = [:]
        for node in nodes where !node.isDirectory && !node.isSymlink {
            guard let size = node.size, size > 0, !node.notDownloaded else { continue }
            bySize[size, default: []].append(node)
        }
        let candidates = bySize.filter { $0.value.count > 1 }
        let candidateCount = candidates.values.reduce(0) { $0 + $1.count }
        var hashedCount = 0

        var groups: [DuplicateGroup] = []
        var cancelled = false
        for (_, files) in candidates.sorted(by: { $0.key > $1.key }) {
            if Task.isCancelled { cancelled = true; break }
            var byHash: [String: [NodeRecord]] = [:]
            for file in files {
                let url = sourceRoot.appending(path: file.relativePath)
                do {
                    let result = try Checksummer.sha256(of: url)
                    byHash[result.hex, default: []].append(file)
                    hashedCount += 1
                    onProgress?(hashedCount, candidateCount)
                } catch is CancellationError {
                    cancelled = true
                    break
                } catch {
                    continue
                }
            }
            if cancelled { break }
            for (hash, group) in byHash where group.count > 1 {
                groups.append(DuplicateGroup(hash: hash, size: files.first?.size ?? 0, nodes: group))
            }
        }
        groups.sort { ($0.nodes.count, $0.size) > ($1.nodes.count, $1.size) }
        return Report(groups: groups, hashedCount: hashedCount, candidateCount: candidateCount, cancelled: cancelled)
    }
}
