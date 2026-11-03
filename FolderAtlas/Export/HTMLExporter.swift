import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Self-contained HTML export: inline CSS (light+dark), inline vanilla JS search,
/// optional embedded JPEG thumbnails as data URIs. No external resources.
enum HTMLExporter {

    static let thumbnailLimit = 400

    static func export(header: SnapshotHeader,
                       columns: [ExportColumn],
                       rows: [RowBuilder.Row],
                       totals: [ExportCell]?,
                       options: ExportOptions) throws -> Data {
        var thumbnails: [String: String] = [:]
        if options.includeThumbnails {
            var generated = 0
            for row in rows where generated < thumbnailLimit {
                let url = absoluteURL(row.node, source: header.sourcePath)
                guard ImageMetadata.isImageFile(url), let uri = Self.thumbnailDataURI(for: url) else { continue }
                thumbnails[row.node.relativePath] = uri
                generated += 1
            }
        }

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(header.displayName)) — FolderAtlas</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 13px/1.45 -apple-system, system-ui, sans-serif; margin: 16px; }
        h1 { font-size: 17px; margin: 0 0 4px; }
        .meta { color: #6e6e73; margin: 0 0 12px; }
        #q { width: 320px; padding: 6px 10px; margin-bottom: 12px; border-radius: 8px;
             border: 1px solid rgba(127,127,127,.4); background: transparent; color: inherit; }
        table { border-collapse: collapse; width: 100%; }
        th, td { text-align: left; padding: 3px 10px; border-bottom: 1px solid rgba(127,127,127,.25);
                 white-space: nowrap; max-width: 480px; overflow: hidden; text-overflow: ellipsis; }
        thead th { position: sticky; top: 0; background: Canvas; cursor: default; font-weight: 600; }
        tr.folder td { font-weight: 600; }
        tr:hover td { background: rgba(127,127,127,.08); }
        a { color: inherit; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .num { text-align: right; font-variant-numeric: tabular-nums; }
        img.thumb { width: 48px; height: 48px; object-fit: cover; border-radius: 4px; vertical-align: middle; }
        tfoot td { font-weight: 600; border-top: 2px solid rgba(127,127,127,.5); }
        </style>
        </head>
        <body>
        <h1>\(escape(header.displayName))</h1>
        <p class="meta">\(escape(header.sourcePath)) · \(escape(Fmt.iso8601(header.createdAt))) ·
        \(rows.count) rows · \(escape(header.scanSettings.summary))</p>
        <input id="q" type="search" placeholder="Filter rows…" autocomplete="off">
        <table>
        <thead><tr>
        """
        for column in columns {
            html += "<th>\(escape(column.title))</th>"
        }
        html += "</tr></thead><tbody>"

        for row in rows {
            let depth = row.node.relativePath.isEmpty ? 0 : row.node.relativePath.components(separatedBy: "/").count - 1
            let classes = row.node.isDirectory ? "folder" : ""
            let indent = "padding-left:calc(10px + \(depth) * 16px);"
            let search = escape(row.node.name + " " + row.node.relativePath)
            html += "<tr class=\"\(classes)\" data-s=\"\(search)\">"
            for (index, column) in columns.enumerated() {
                let cell = row.cells[index]
                let style = column == .name ? indent : ""
                let numericClass = cell.number != nil && !options.humanReadable ? " class=\"num\"" : ""
                var content: String
                if column == .name, let display = cell.display {
                    let fileURL = absoluteURL(row.node, source: header.sourcePath)
                        .absoluteString
                        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                    let thumb = thumbnails[row.node.relativePath]
                        .map { "<img class=\"thumb\" src=\"\($0)\" alt=\"\">" } ?? ""
                    content = thumb + "<a href=\"\(fileURL)\">\(escape(display))</a>"
                } else {
                    content = escape(cell.display ?? "")
                }
                html += "<td style=\"\(style)\"\(numericClass)>\(content)</td>"
            }
            html += "</tr>"
        }
        html += "</tbody>"
        if let totals {
            html += "<tfoot><tr>"
            for cell in totals {
                html += "<td>\(escape(cell.display ?? ""))</td>"
            }
            html += "</tr></tfoot>"
        }
        html += """
        </table>
        <script>
        const input = document.getElementById('q');
        input.addEventListener('input', () => {
          const v = input.value.toLowerCase();
          document.querySelectorAll('tbody tr').forEach(tr => {
            tr.style.display = tr.dataset.s.toLowerCase().includes(v) ? '' : 'none';
          });
        });
        </script>
        </body>
        </html>
        """
        return Data(html.utf8)
    }

    static func thumbnailDataURI(for url: URL) -> String? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return "data:image/jpeg;base64," + (output as Data).base64EncodedString()
    }

    static func absoluteURL(_ node: NodeRecord, source: String) -> URL {
        if node.relativePath.isEmpty { return URL(fileURLWithPath: source) }
        return URL(fileURLWithPath: source).appending(path: node.relativePath)
    }

    static func escape(_ text: String) -> String {
        text.replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
    }
}
