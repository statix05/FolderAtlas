import Foundation

/// Fast, locale-independent sort keys.
///
/// Sorting by `localizedStandardCompare` (ICU collation) on every comparison
/// costs microseconds per pair — with ~1M rows a single column click performs
/// tens of millions of comparisons and freezes the UI. Instead, a key is
/// computed once per node (at scan time, or when loading older snapshots) and
/// afterwards compared with plain byte comparison (`String <`).
///
/// The key = compatibility-decomposed, lowercased text where every digit run
/// is left-padded with `0` to `padWidth` significant digits. Byte comparison
/// of such keys yields Finder-like numeric ordering ("file2" < "file10").
enum SortKey {

    /// Significant digits preserved per numeric run. Longer runs are emitted
    /// unpadded (they then sort after padded short runs, which is wrong only
    /// for file names with more than 8 significant digits).
    private static let padWidth = 8

    /// Builds the sort key: compatibility decomposition, stripping combining
    /// marks (é → e), lowercasing, then numeric padding.
    static func make(_ string: String) -> String {
        var folded = string.decomposedStringWithCompatibilityMapping
        folded = folded.applyingTransform(.stripCombiningMarks, reverse: false) ?? folded
        folded = folded.lowercased()
        var out: [UInt8] = []
        out.reserveCapacity(folded.utf8.count + 16)
        let view = folded.utf8
        var i = view.startIndex
        let end = view.endIndex
        while i < end {
            let byte = view[i]
            if isDigit(byte) {
                // Find the run end and collect significant digits.
                var significant: [UInt8] = []
                var j = i
                while j < end, isDigit(view[j]) {
                    if !significant.isEmpty || view[j] != 48 {
                        significant.append(view[j])
                    }
                    j = view.index(after: j)
                }
                let padding = significant.count <= padWidth ? padWidth - significant.count : 0
                out.append(contentsOf: repeatElement(48, count: padding))
                out.append(contentsOf: significant)
                i = j
            } else {
                out.append(byte)
                i = view.index(after: i)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Compares already-encoded keys (hot path).
    static func compareKeys(_ a: String, _ b: String) -> ComparisonResult {
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    /// Convenience for tests and one-off comparisons: builds keys, then compares.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        compareKeys(make(a), make(b))
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }
}
