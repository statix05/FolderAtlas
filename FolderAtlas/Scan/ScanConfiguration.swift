import Foundation

/// Options of a single scan run. Persisted inside every snapshot header.
struct ScanConfiguration: Codable, Sendable, Hashable {
    /// Include hidden files and folders.
    var includeHidden: Bool
    /// Descend into application bundles and other packages.
    var includePackageContents: Bool
    /// Compute recursive folder sizes and descendant counts during the scan.
    var computeFolderSizes: Bool
    /// Optional maximum recursion depth (nil = unlimited).
    var maxDepth: Int?

    init(includeHidden: Bool = true,
         includePackageContents: Bool = true,
         computeFolderSizes: Bool = true,
         maxDepth: Int? = nil) {
        self.includeHidden = includeHidden
        self.includePackageContents = includePackageContents
        self.computeFolderSizes = computeFolderSizes
        self.maxDepth = maxDepth
    }
}

extension ScanConfiguration {
    /// Human readable summary for the inspector and exports.
    var summary: String {
        var parts: [String] = []
        parts.append(includeHidden ? "hidden: on" : "hidden: off")
        parts.append(includePackageContents ? "packages: contents" : "packages: boundary")
        parts.append(computeFolderSizes ? "folder sizes: on" : "folder sizes: off")
        if let maxDepth { parts.append("depth: \(maxDepth)") }
        return parts.joined(separator: ", ")
    }
}
