import Foundation

/// View-level toggles backed by UserDefaults (read on the hot path is fine —
/// defaults are process-cached).
enum ViewSettings {
    static let combinedSizeKey = "columns.combinedSize"

    /// Combine «Size» and «Size on disk» into one slash-separated column
    /// (owner request; default ON, can be switched off).
    static var combinedSize: Bool {
        UserDefaults.standard.object(forKey: combinedSizeKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: combinedSizeKey)
    }
}

enum Fmt {
    static let unknown = "—"

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return unknown }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// «12 МБ / 45 МБ» — logical size / on-disk size for the combined column.
    /// Falls back to the plain size when the combination is off or the on-disk
    /// value is unknown. Files only (folders have no meaningful split here).
    static func sizeCombined(_ logical: Int64?, _ onDisk: Int64?, combined: Bool) -> String {
        guard combined, let onDisk, logical != nil else { return size(logical) }
        return "\(size(logical)) / \(size(onDisk))"
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
