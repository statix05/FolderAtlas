import Foundation

enum Fmt {
    static let unknown = "—"

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return unknown }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return unknown }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func iso8601(_ date: Date?) -> String {
        guard let date else { return unknown }
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash).dateTimeSeparator(.standard))
    }

    static func count(_ value: Int64?) -> String {
        guard let value else { return unknown }
        return value.formatted(.number.grouping(.automatic))
    }

    static func seconds(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return unknown }
        return Duration.seconds(value).formatted(.time(pattern: .minuteSecond))
    }

    static func dimensions(_ width: Int?, _ height: Int?) -> String {
        guard let width, let height else { return unknown }
        return "\(width) × \(height)"
    }

    static func coordinates(_ lat: Double?, _ lon: Double?) -> String {
        guard let lat, let lon else { return unknown }
        return String(format: "%.5f, %.5f", lat, lon)
    }
}

/// Formatters shared by UI, exports and the inspector.
enum NodeFormatters {
    static func kindName(_ kind: NodeKind) -> String {
        switch kind {
        case .file: return String(localized: "File")
        case .folder: return String(localized: "Folder")
        case .symlink: return String(localized: "Symlink")
        case .package: return String(localized: "Package")
        }
    }
}
