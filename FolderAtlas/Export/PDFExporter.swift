import Foundation
import CoreText
import CoreGraphics

/// Paginated PDF tables via Core Graphics + Core Text. No external dependencies.
enum PDFExporter {

    static func export(header: SnapshotHeader,
                       columns: [ExportColumn],
                       rows: [RowBuilder.Row],
                       totals: [ExportCell]?) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape
        let margin: CGFloat = 32
        let rowHeight: CGFloat = 13
        let contentRect = CGRect(x: margin, y: margin + 14,
                                 width: pageRect.width - margin * 2,
                                 height: pageRect.height - margin * 2 - 14)
        let rowsPerPage = max(1, Int((contentRect.height - rowHeight) / rowHeight))
        let totalPages = max(1, (rows.count + rowsPerPage - 1) / rowsPerPage)

        let widths = columnWidths(count: columns.count, totalWidth: contentRect.width)

        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "folderatlas-export-\(UUID().uuidString).pdf")
        let consumer = CGDataConsumer(url: tempURL as CFURL)
        var mediaBox = pageRect
        let auxiliary = [
            kCGPDFContextTitle: header.displayName,
            kCGPDFContextCreator: "FolderAtlas"
        ] as CFDictionary
        guard let unwrappedConsumer = consumer,
              let context = CGContext(consumer: unwrappedConsumer, mediaBox: &mediaBox, auxiliary) else {
            return Data()
        }

        let bodyFont = CTFontCreateWithName("Helvetica" as CFString, 8.5, nil)
        let boldFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 8.5, nil)
        let titleFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)

        var pageIndex = 0
        var rowCursor = 0
        while rowCursor < rows.count || pageIndex == 0 {
            context.beginPDFPage(nil)
            // Title on the first page.
            if pageIndex == 0 {
                drawText(header.displayName, at: CGPoint(x: margin, y: pageRect.height - margin),
                         font: titleFont, maxWidth: contentRect.width, context: context)
                drawText("\(header.sourcePath)  ·  \(Fmt.iso8601(header.createdAt))",
                         at: CGPoint(x: margin, y: pageRect.height - margin - 14),
                         font: bodyFont, maxWidth: contentRect.width, context: context)
            }
            var y = contentRect.maxY - rowHeight
            // Header row on every page. Rows are drawn inside the content margins.
            context.saveGState()
            context.translateBy(x: margin, y: 0)
            drawRow(cells: columns.map { ExportCell($0.title) }, y: y, widths: widths,
                    font: boldFont, context: context)
            y -= rowHeight

            let pageEnd = min(rowCursor + rowsPerPage, rows.count)
            while rowCursor < pageEnd {
                drawRow(cells: rows[rowCursor].cells, y: y, widths: widths,
                        font: bodyFont, context: context)
                y -= rowHeight
                rowCursor += 1
            }
            // Totals on the very last page.
            if rowCursor >= rows.count, let totals {
                context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
                context.setLineWidth(0.5)
                context.move(to: CGPoint(x: contentRect.minX, y: y + rowHeight - 2))
                context.addLine(to: CGPoint(x: contentRect.maxX, y: y + rowHeight - 2))
                context.strokePath()
                drawRow(cells: totals, y: y, widths: widths, font: boldFont, context: context)
            }
            context.restoreGState()
            // Page number.
            let footer = String(localized: "Page \(pageIndex + 1) of \(totalPages)")
            drawText(footer, at: CGPoint(x: margin, y: margin / 2), font: bodyFont,
                     maxWidth: contentRect.width, context: context)
            context.endPDFPage()
            pageIndex += 1
            if pageIndex > 10000 { break } // hard safety stop
        }
        context.closePDF()
        let data = (try? Data(contentsOf: tempURL)) ?? Data()
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }

    private static func columnWidths(count: Int, totalWidth: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        var weights: [CGFloat] = Array(repeating: 1, count: count)
        if count > 0 { weights[0] = 3 } // name column is wider
        if count > 1 { weights[min(1, count - 1)] = 2 }
        let sum = weights.reduce(0, +)
        return weights.map { $0 / sum * totalWidth }
    }

    private static func drawRow(cells: [ExportCell], y: CGFloat, widths: [CGFloat], font: CTFont, context: CGContext) {
        var x: CGFloat = 0
        for (index, cell) in cells.enumerated() where index < widths.count {
            drawText(cell.display ?? "", at: CGPoint(x: x + 2, y: y), font: font,
                     maxWidth: widths[index] - 4, context: context)
            x += widths[index]
        }
    }

    private static func drawText(_ text: String, at point: CGPoint, font: CTFont,
                                 maxWidth: CGFloat, context: CGContext) {
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(gray: 0.1, alpha: 1)
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        var line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if width > maxWidth {
            if let truncated = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, nil) {
                line = truncated
            }
        }
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
