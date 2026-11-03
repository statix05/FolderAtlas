import Foundation

/// Combinable filter for the node table and exports.
struct FilterCriteria: Sendable, Equatable {
    enum KindOption: String, CaseIterable, Sendable, Identifiable {
        case files, folders, packages, symlinks
        var id: String { rawValue }
    }

    enum HiddenMode: String, CaseIterable, Sendable {
        case any, onlyHidden, noHidden
    }

    enum Availability: String, CaseIterable, Sendable {
        case any, available, unavailable
    }

    var searchText: String = ""
    var kinds: Set<KindOption> = []
    var extensions: Set<String> = []
    var tags: Set<String> = []
    var minSize: Int64?
    var maxSize: Int64?
    var createdFrom: Date?
    var createdTo: Date?
    var modifiedFrom: Date?
    var modifiedTo: Date?
    var hiddenMode: HiddenMode = .any
    var onlySymlinks = false
    var onlyWithError = false
    var onlyNotDownloaded = false
    var availability: Availability = .any

    var isEmpty: Bool {
        self == FilterCriteria()
    }

    /// Checks a node against every active criterion. Availability probes the
    /// filesystem with a cheap stat — only when the filter is actually active.
    func matches(_ node: NodeRecord) -> Bool {
        if !searchText.isEmpty {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                if !node.name.localizedStandardContains(query)
                    && !node.relativePath.localizedStandardContains(query) {
                    return false
                }
            }
        }

        if !kinds.isEmpty {
            let ok: Bool
            switch node.kind {
            case .file: ok = kinds.contains(.files)
            case .folder: ok = kinds.contains(.folders)
            case .package: ok = kinds.contains(.packages)
            case .symlink: ok = kinds.contains(.symlinks)
            }
            if !ok { return false }
        }

        if !extensions.isEmpty {
            guard let ext = node.ext, extensions.contains(ext) else { return false }
        }

        if !tags.isEmpty {
            let nodeTags = Set(node.tags ?? [])
            guard !tags.isDisjoint(with: nodeTags) else { return false }
        }

        if let minSize, minSize > 0 {
            guard let size = node.size, size >= minSize else { return false }
        }
        if let maxSize, maxSize > 0 {
            guard let size = node.size, size <= maxSize else { return false }
        }

        if let createdFrom {
            guard let created = node.created, created >= createdFrom else { return false }
        }
        if let createdTo {
            guard let created = node.created, created <= createdTo else { return false }
        }
        if let modifiedFrom {
            guard let modified = node.modified, modified >= modifiedFrom else { return false }
        }
        if let modifiedTo {
            guard let modified = node.modified, modified <= modifiedTo else { return false }
        }

        switch hiddenMode {
        case .any: break
        case .onlyHidden: if !node.isHidden { return false }
        case .noHidden: if node.isHidden { return false }
        }

        if onlySymlinks && !node.isSymlink { return false }
        if onlyWithError && node.error == nil { return false }
        if onlyNotDownloaded && !node.notDownloaded { return false }

        switch availability {
        case .any: break
        case .available, .unavailable:
            let exists = FileManager.default.fileExists(atPath: absolutePath(node))
            if availability == .available && !exists { return false }
            if availability == .unavailable && exists { return false }
        }
        return true
    }

    func absolutePath(_ node: NodeRecord, sourcePath: String = "") -> String {
        if node.relativePath.isEmpty { return sourcePath }
        return sourcePath.isEmpty ? node.relativePath : sourcePath + "/" + node.relativePath
    }
}
