import Foundation

/// Minimal OOXML SpreadsheetML writer. Produces a real .xlsx package
/// (ZIP container + workbook/worksheet/styles XML with inline strings) —
/// it is NOT a renamed CSV. Numeric cells stay numeric.
enum XLSXExporter {

    static func export(header: SnapshotHeader,
                       columns: [ExportColumn],
                       rows: [RowBuilder.Row],
                       totals: [ExportCell]?,
                       options: ExportOptions) throws -> Data {
        var sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols>
        """
        for index in 0..<max(1, columns.count) {
            let width = index == 0 ? 40.0 : 22.0
            sheet += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }
        sheet += "</cols><sheetData>"

        var rowNumber = 0
        func addRow(cells: [ExportCell], bold: Bool = false) {
            rowNumber += 1
            var rowXML = "<row r=\"\(rowNumber)\">"
            for (index, cell) in cells.enumerated() {
                let reference = "\(columnLetter(index))\(rowNumber)"
                let style = bold ? " s=\"1\"" : ""
                if let number = cell.number, !options.humanReadable {
                    rowXML += "<c r=\"\(reference)\" t=\"n\"\(style)><v>\(number)</v></c>"
                } else if let display = cell.display, !display.isEmpty {
                    rowXML += "<c r=\"\(reference)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(escape(display))</t></is></c>"
                }
            }
            rowXML += "</row>"
            sheet += rowXML
        }

        addRow(cells: columns.map { ExportCell($0.title) }, bold: true)
        for row in rows {
            addRow(cells: row.cells)
        }
        if let totals {
            addRow(cells: totals, bold: true)
        }
        sheet += "</sheetData></worksheet>"

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Files" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2">
        <font><sz val="10"/><name val="Helvetica"/></font>
        <font><b/><sz val="10"/><name val="Helvetica"/></font>
        </fonts>
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="2">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        </cellXfs>
        </styleSheet>
        """

        let entries: [ZipWriter.Entry] = [
            ZipWriter.Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZipWriter.Entry(name: "_rels/.rels", data: Data(rootRels.utf8)),
            ZipWriter.Entry(name: "xl/workbook.xml", data: Data(workbook.utf8)),
            ZipWriter.Entry(name: "xl/_rels/workbook.xml.rels", data: Data(workbookRels.utf8)),
            ZipWriter.Entry(name: "xl/styles.xml", data: Data(styles.utf8)),
            ZipWriter.Entry(name: "xl/worksheets/sheet1.xml", data: Data(sheet.utf8))
        ]
        let target = FileManager.default.temporaryDirectory
            .appending(path: "folderatlas-\(UUID().uuidString).xlsx")
        try ZipWriter.write(entries: entries, to: target)
        let data = try Data(contentsOf: target)
        try? FileManager.default.removeItem(at: target)
        return data
    }

    static func columnLetter(_ index: Int) -> String {
        var value = index + 1
        var letters = ""
        while value > 0 {
            let remainder = (value - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + remainder))) + letters
            value = (value - 1) / 26
        }
        return letters
    }

    static func escape(_ text: String) -> String {
        text.replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
            .replacing("'", with: "&apos;")
    }
}
