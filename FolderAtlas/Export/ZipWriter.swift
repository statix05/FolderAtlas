import Foundation
import Compression

/// Minimal ZIP writer (store + raw-deflate entries) used by the XLSX exporter.
/// Raw DEFLATE from Apple's Compression framework matches ZIP method 8.
enum ZipWriter {

    struct Entry {
        var name: String
        var data: Data
    }

    enum ZipError: LocalizedError {
        case deflateFailed
        var errorDescription: String? { "ZIP compression failed" }
    }

    static func write(entries: [Entry], to url: URL) throws {
        var body = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let compressed: Data
            var method: UInt16 = 8
            if let deflated = deflate(entry.data), deflated.count < entry.data.count {
                compressed = deflated
            } else {
                compressed = entry.data
                method = 0
            }
            let dosTime = dosTime(Date())

            var local = Data()
            local.appendLE(UInt32(0x04034b50))
            local.appendLE(UInt16(20))          // version needed
            local.appendLE(UInt16(0))           // flags
            local.appendLE(method)
            local.appendLE(dosTime.time)
            local.appendLE(dosTime.date)
            local.appendLE(crc)
            local.appendLE(UInt32(compressed.count))
            local.appendLE(UInt32(entry.data.count))
            local.appendLE(UInt16(nameData.count))
            local.appendLE(UInt16(0))           // extra len
            local.append(nameData)
            body.append(local)
            body.append(compressed)

            var central = Data()
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))        // version made by
            central.appendLE(UInt16(20))        // version needed
            central.appendLE(UInt16(0))         // flags
            central.appendLE(method)
            central.appendLE(dosTime.time)
            central.appendLE(dosTime.date)
            central.appendLE(crc)
            central.appendLE(UInt32(compressed.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))         // extra
            central.appendLE(UInt16(0))         // comment
            central.appendLE(UInt16(0))         // disk number
            central.appendLE(UInt16(0))         // internal attrs
            central.appendLE(UInt32(0))         // external attrs
            central.appendLE(offset)
            central.append(nameData)
            centralDirectory.append(central)

            offset += UInt32(local.count + compressed.count)
        }

        var eocd = Data()
        eocd.appendLE(UInt32(0x06054b50))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt16(entries.count))
        eocd.appendLE(UInt32(centralDirectory.count))
        eocd.appendLE(offset)
        eocd.appendLE(UInt16(0))

        let result = body + centralDirectory + eocd
        try result.write(to: url, options: [.atomic])
    }

    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let source = [UInt8](data)
        var destination = [UInt8](repeating: 0, count: source.count + 64)
        let written = compression_encode_buffer(&destination, destination.count,
                                                source, source.count,
                                                nil, COMPRESSION_ZLIB)
        guard written > 0 else { return nil }
        return Data(destination.prefix(written))
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func dosTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, components.year ?? 1980)
        let dateValue = UInt16((year - 1980) << 9 | (components.month ?? 1) << 5 | (components.day ?? 1))
        let timeValue = UInt16((components.hour ?? 0) << 11 | (components.minute ?? 0) << 5 | (components.second ?? 0) / 2)
        return (timeValue, dateValue)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
