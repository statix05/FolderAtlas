import Foundation
import CryptoKit

/// Streaming SHA-256 for large files.
enum Checksummer {
    struct Result: Sendable {
        var hex: String
        var bytesHashed: Int64
    }

    static func sha256(of url: URL) throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var hashed: Int64 = 0
        let chunkSize = 1 << 20
        while true {
            if Task.isCancelled { throw CancellationError() }
            let chunk = try autoreleasepool { () -> Data in
                try handle.read(upToCount: chunkSize) ?? Data()
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            hashed += Int64(chunk.count)
        }
        let digest = hasher.finalize()
        var hex = ""
        hex.reserveCapacity(64)
        for byte in digest {
            hex += String(format: "%02x", byte)
        }
        return Result(hex: hex, bytesHashed: hashed)
    }
}
