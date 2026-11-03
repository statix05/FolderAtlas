import Foundation

/// Background "enrichment" passes: expensive metadata (checksums, EXIF, media info)
/// computed on demand for a subset of nodes, with bounded concurrency and cancellation.
enum EnrichmentService {

    struct MediaOutcome: Sendable {
        var imageInfo: ImageInfo?
        var mediaInfo: MediaInfo?
        var error: String?
    }

    /// Streaming SHA-256 for the given node ids. Skips folders and cloud placeholders.
    static func checksums(for ids: [Int64],
                          nodes: [NodeRecord],
                          sourceRoot: URL,
                          onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> [Int64: String] {
        var results: [Int64: String] = [:]
        let targets = ids.compactMap { id -> (Int64, URL)? in
            guard let node = nodes.first(where: { $0.id == id }), !node.notDownloaded, !node.isDirectory else { return nil }
            return (id, sourceRoot.appending(path: node.relativePath))
        }
        let total = targets.count
        var done = 0
        for chunk in targets.chunksForConcurrency(4) {
            if Task.isCancelled { break }
            let chunkResults = await withTaskGroup(of: (Int64, String?).self, returning: [(Int64, String?)].self) { group in
                for (id, url) in chunk {
                    group.addTask {
                        do {
                            let result = try Checksummer.sha256(of: url)
                            return (id, result.hex)
                        } catch {
                            return (id, nil)
                        }
                    }
                }
                var collected: [(Int64, String?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (id, hex) in chunkResults {
                if let hex { results[id] = hex }
                done += 1
            }
            onProgress?(done, total)
        }
        return results
    }

    /// EXIF / media metadata extraction for the given node ids.
    static func media(for ids: [Int64],
                      nodes: [NodeRecord],
                      sourceRoot: URL,
                      onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> [Int64: MediaOutcome] {
        var results: [Int64: MediaOutcome] = [:]
        let lock = NSLock()
        let targets = ids.compactMap { id -> (Int64, NodeRecord)? in
            guard let node = nodes.first(where: { $0.id == id }), !node.isDirectory else { return nil }
            return (id, node)
        }
        let total = targets.count
        var done = 0
        for chunk in targets.chunksForConcurrency(4) {
            if Task.isCancelled { break }
            let chunkResults = await withTaskGroup(of: (Int64, MediaOutcome).self, returning: [(Int64, MediaOutcome)].self) { group in
                for (id, node) in chunk {
                    let url = sourceRoot.appending(path: node.relativePath)
                    group.addTask {
                        if node.notDownloaded {
                            return (id, MediaOutcome(imageInfo: nil, mediaInfo: nil,
                                                     error: String(localized: "Not downloaded from iCloud")))
                        }
                        var outcome = MediaOutcome(imageInfo: nil, mediaInfo: nil, error: nil)
                        if ImageMetadata.isImageFile(url) {
                            outcome.imageInfo = ImageMetadata.extract(url: url)
                        } else if MediaMetadata.isMediaFile(url) {
                            outcome.mediaInfo = await MediaMetadata.extract(url: url)
                        }
                        return (id, outcome)
                    }
                }
                var collected: [(Int64, MediaOutcome)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (id, outcome) in chunkResults {
                results[id] = outcome
                done += 1
            }
            onProgress?(done, total)
        }
        return results
    }
}

private extension Array {
    /// Splits the array into consecutive chunks of at most `size` elements.
    func chunksForConcurrency(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            chunks.append(Array(self[index..<Swift.min(index + size, endIndex)]))
            index += size
        }
        return chunks
    }
}
