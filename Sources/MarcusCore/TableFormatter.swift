import Foundation

/// Aligns the columns of the GFM table under the caret (Format → Format
/// Table, ⌃⌘T): every cell padded to its column's width, the delimiter
/// row stretched to match with its `:` alignment markers kept, outer pipes
/// normalized. Pure text in, text out — the editor applies the result as
/// one undoable replacement.
///
/// What counts as the table: the run of pipe-bearing lines around the
/// caret whose second line is a delimiter row (`| --- | :-: |`). Lines
/// inside a fenced code block or the front matter never qualify. Rows with
/// fewer cells than the widest row are padded with empty cells, never
/// trimmed: nothing the user typed is dropped.
public enum TableFormatter {

    public struct Edit: Equatable, Sendable {
        /// UTF-16 range of the table's lines in the original text, without
        /// the trailing line terminator.
        public let range: NSRange
        public let replacement: String
        /// Where the caret lands inside `replacement`: same row, same cell,
        /// same offset into the cell's text (clamped to its length).
        public let caretOffset: Int
    }

    public enum Alignment: Equatable, Sendable {
        case none, left, center, right
    }

    /// The formatted table around `offset`, or nil when the caret is not
    /// in one. The replacement may equal the original text (already
    /// aligned); the caller decides whether that is worth an edit.
    public static func edit(in text: String, caretAt offset: Int) -> Edit? {
        guard let table = locate(in: text, caretAt: offset) else { return nil }
        let formatted = format(table.rows, caretRow: table.caretRow, caretInLine: table.caretInLine)
        return Edit(range: table.range, replacement: formatted.lines.joined(separator: table.terminator),
                    caretOffset: formatted.caretOffset(terminatorLength: (table.terminator as NSString).length))
    }

    /// Whether `offset` sits in a table (menus enable themselves on this).
    public static func isInTable(_ text: String, caretAt offset: Int) -> Bool {
        locate(in: text, caretAt: offset) != nil
    }

    /// Tab between cells: the table re-aligned plus the next (or previous)
    /// cell's text to select, skipping the delimiter row. Tab on the last
    /// cell of the last row appends an empty row; Shift-Tab on the first
    /// header cell stays there.
    public struct CellMove: Equatable, Sendable {
        public let edit: Edit
        /// Cell text to select, absolute in the text after the edit.
        public let selection: NSRange
    }

    public static func moveCell(in text: String, caretAt offset: Int, forward: Bool) -> CellMove? {
        guard let table = locate(in: text, caretAt: offset) else { return nil }
        var rows = table.rows
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0, rows.count >= 2 else { return nil }
        var (row, cell) = currentCell(in: rows, caretRow: table.caretRow, caretInLine: table.caretInLine)
        if row == 1 {
            // The delimiter row has no cells to fill: down to the first body
            // cell, or up to the header cell above.
            if forward {
                (row, cell) = (2, 0)
                if rows.count < 3 {
                    rows.append((0..<columns).map { _ in Cell(text: "", range: NSRange(location: 0, length: 0)) })
                }
            } else {
                row = 0
            }
        } else if forward {
            cell += 1
            if cell >= columns {
                cell = 0
                row += row == 0 ? 2 : 1
                if row >= rows.count {
                    rows.append((0..<columns).map { _ in Cell(text: "", range: NSRange(location: 0, length: 0)) })
                }
            }
        } else {
            cell -= 1
            if cell < 0 {
                row -= row == 2 ? 2 : 1
                if row < 0 { (row, cell) = (0, 0) } else { cell = columns - 1 }
            }
        }
        let formatted = format(rows, caretRow: row, caretInLine: 0)
        let terminatorLength = (table.terminator as NSString).length
        var lineStart = 0
        for index in 0..<row { lineStart += (formatted.lines[index] as NSString).length + terminatorLength }
        let cellRange = formatted.cellRanges[row][cell]
        let edit = Edit(range: table.range, replacement: formatted.lines.joined(separator: table.terminator),
                        caretOffset: lineStart + cellRange.location)
        return CellMove(edit: edit, selection: NSRange(location: table.range.location + lineStart + cellRange.location,
                                                        length: cellRange.length))
    }

    /// Formats a table given as lines (header, delimiter, body…).
    public static func formattedLines(_ lines: [String]) -> [String] {
        format(lines.map { cells(of: $0) }, caretRow: 0, caretInLine: 0).lines
    }

    // MARK: - Locating

    struct Located {
        var rows: [[Cell]]
        var range: NSRange
        var caretRow: Int
        var caretInLine: Int
        var terminator: String
    }

    static func locate(in text: String, caretAt offset: Int) -> Located? {
        let ns = text as NSString
        let lines = physicalLines(ns)
        guard !lines.isEmpty else { return nil }
        let caretLine = lineIndex(in: lines, at: min(max(offset, 0), ns.length))

        if let front = FrontMatter.block(in: text), caretLine < front.lineCount { return nil }
        if isInsideFence(lines, lineIndex: caretLine) { return nil }

        guard isRowLike(lines[caretLine].text) else { return nil }
        var first = caretLine
        while first > 0, isRowLike(lines[first - 1].text) { first -= 1 }
        var last = caretLine
        while last + 1 < lines.count, isRowLike(lines[last + 1].text) { last += 1 }

        // The table starts on the header just above the first delimiter
        // row that the caret is not above.
        guard let delimiter = (first + 1...last).first(where: { isDelimiterRow(lines[$0].text) && caretLine >= $0 - 1 })
        else { return nil }
        let start = delimiter - 1
        let terminator = ns.range(of: "\r\n").location == NSNotFound ? "\n" : "\r\n"
        return Located(
            rows: lines[start...last].map { cells(of: $0.text) },
            range: NSRange(location: lines[start].range.location,
                           length: lines[last].range.upperBound - lines[start].range.location),
            caretRow: caretLine - start,
            caretInLine: offset - lines[caretLine].range.location,
            terminator: terminator)
    }

    /// The cell under the caret in the original rows and the offset into it.
    static func currentCell(in rows: [[Cell]], caretRow: Int, caretInLine: Int) -> (row: Int, cell: Int) {
        let row = min(max(caretRow, 0), rows.count - 1)
        let cell = rows[row].lastIndex(where: { $0.range.location <= caretInLine }) ?? 0
        return (row, cell)
    }

    // MARK: - Formatting

    struct Formatted {
        var lines: [String]
        /// Per row, the UTF-16 range of each cell's text inside its line
        /// (the delimiter row's are zero-length).
        var cellRanges: [[NSRange]]
        /// Row and UTF-16 offset of the caret inside that row.
        var caretRow: Int
        var caretInRow: Int

        func caretOffset(terminatorLength: Int) -> Int {
            var offset = 0
            for row in 0..<caretRow {
                offset += (lines[row] as NSString).length + terminatorLength
            }
            return offset + caretInRow
        }
    }

    static func format(_ rows: [[Cell]], caretRow: Int, caretInLine: Int) -> Formatted {
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0, rows.count >= 2 else {
            let lines = rows.map { row in row.map(\.text).joined(separator: " | ") }
            return Formatted(lines: lines, cellRanges: rows.map { $0.map(\.range) },
                             caretRow: caretRow, caretInRow: caretInLine)
        }
        let alignments: [Alignment] = (0..<columns).map { column in
            column < rows[1].count ? alignment(of: rows[1][column].text) : .none
        }
        var widths = [Int](repeating: 3, count: columns)
        for (index, row) in rows.enumerated() where index != 1 {
            for (column, cell) in row.enumerated() {
                widths[column] = max(widths[column], displayWidth(cell.text))
            }
        }

        // The caret's cell and its offset into that cell's text, in the
        // original row — re-placed in the formatted one below.
        let (caretRowClamped, caretCell) = currentCell(in: rows, caretRow: caretRow, caretInLine: caretInLine)
        let caretCellRange = rows[caretRowClamped][caretCell].range
        let caretInCell = min(max(caretInLine - caretCellRange.location, 0), caretCellRange.length)

        var lines: [String] = []
        var cellRanges: [[NSRange]] = []
        var caretInRow = 0
        for (index, row) in rows.enumerated() {
            var line = "|"
            var ranges: [NSRange] = []
            for column in 0..<columns {
                let width = widths[column]
                let alignment = alignments[column]
                if index == 1 {
                    line += " "
                    ranges.append(NSRange(location: (line as NSString).length, length: 0))
                    line += delimiter(width: width, alignment: alignment) + " |"
                    continue
                }
                let text = column < row.count ? row[column].text : ""
                let padding = max(0, width - displayWidth(text))
                let (left, right): (Int, Int) = switch alignment {
                case .right: (padding, 0)
                case .center: (padding / 2, padding - padding / 2)
                case .left, .none: (0, padding)
                }
                line += " " + String(repeating: " ", count: left)
                ranges.append(NSRange(location: (line as NSString).length, length: (text as NSString).length))
                line += text + String(repeating: " ", count: right) + " |"
            }
            if index == caretRowClamped {
                let range = ranges[min(caretCell, ranges.count - 1)]
                caretInRow = range.location + min(caretInCell, range.length)
            }
            lines.append(line)
            cellRanges.append(ranges)
        }
        return Formatted(lines: lines, cellRanges: cellRanges, caretRow: caretRowClamped, caretInRow: caretInRow)
    }

    static func delimiter(width: Int, alignment: Alignment) -> String {
        switch alignment {
        case .none: String(repeating: "-", count: width)
        case .left: ":" + String(repeating: "-", count: width - 1)
        case .right: String(repeating: "-", count: width - 1) + ":"
        case .center: ":" + String(repeating: "-", count: width - 2) + ":"
        }
    }

    static func alignment(of delimiterCell: String) -> Alignment {
        let left = delimiterCell.hasPrefix(":")
        let right = delimiterCell.hasSuffix(":") && delimiterCell.count > 1
        switch (left, right) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return .none
        }
    }

    // MARK: - Rows and cells

    struct Cell: Equatable {
        var text: String
        /// UTF-16 range of the trimmed text inside its line.
        var range: NSRange

        init(text: String, range: NSRange) {
            self.text = text
            self.range = range
        }
    }

    /// A line that can belong to a table: not blank, with a pipe in it.
    static func isRowLike(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `| --- | :-: | ---: |`: every cell is dashes with optional colons.
    static func isDelimiterRow(_ line: String) -> Bool {
        let cells = cells(of: line)
        guard !cells.isEmpty, line.contains("-") else { return false }
        return cells.allSatisfy { cell in
            var body = Substring(cell.text)
            if body.hasPrefix(":") { body = body.dropFirst() }
            if body.hasSuffix(":") { body = body.dropLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    /// Splits a row on unescaped pipes, after dropping one leading and one
    /// trailing pipe; cells come trimmed, with their position in the line.
    static func cells(of line: String) -> [Cell] {
        let ns = line as NSString
        // Content bounds: whitespace and the optional outer pipes.
        var start = 0
        var end = ns.length
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        if start < end, ns.character(at: start) == pipe { start += 1 }
        if end > start, ns.character(at: end - 1) == pipe, !isEscaped(ns, at: end - 1) { end -= 1 }

        var cells: [Cell] = []
        var cellStart = start
        var index = start
        while index <= end {
            if index == end || (ns.character(at: index) == pipe && !isEscaped(ns, at: index)) {
                var a = cellStart
                var b = index
                while a < b, isSpace(ns.character(at: a)) { a += 1 }
                while b > a, isSpace(ns.character(at: b - 1)) { b -= 1 }
                let range = NSRange(location: a, length: b - a)
                cells.append(Cell(text: ns.substring(with: range), range: range))
                cellStart = index + 1
            }
            index += 1
        }
        return cells
    }

    private static let pipe: unichar = 0x7C      // |
    private static let backslash: unichar = 0x5C  // \

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    /// A pipe preceded by an odd run of backslashes is content (`\|`).
    private static func isEscaped(_ ns: NSString, at index: Int) -> Bool {
        var count = 0
        var i = index - 1
        while i >= 0, ns.character(at: i) == backslash { count += 1; i -= 1 }
        return count % 2 == 1
    }

    // MARK: - Width

    /// Columns a string takes in a monospaced editor: East Asian wide and
    /// fullwidth characters and emoji count two, combining marks and
    /// joiners zero, the rest one.
    public static func displayWidth(_ text: String) -> Int {
        var width = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if v == 0x200D || (0xFE00...0xFE0F).contains(v) || (0xE0100...0xE01EF).contains(v) { continue }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format: continue
            default: break
            }
            if isWide(v) || scalar.properties.isEmojiPresentation { width += 2 } else { width += 1 }
        }
        return width
    }

    private static func isWide(_ v: UInt32) -> Bool {
        (0x1100...0x115F).contains(v) || (0x2E80...0x303E).contains(v) || (0x3041...0x33FF).contains(v)
            || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xA000...0xA4CF).contains(v)
            || (0xAC00...0xD7A3).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFE30...0xFE4F).contains(v)
            || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v) || (0x1F300...0x1F64F).contains(v)
            || (0x1F900...0x1F9FF).contains(v) || (0x20000...0x3FFFD).contains(v)
    }

    // MARK: - Lines

    struct Line {
        /// UTF-16 range of the content, terminator excluded.
        var range: NSRange
        var text: String
    }

    static func physicalLines(_ ns: NSString) -> [Line] {
        var lines: [Line] = []
        var position = 0
        while position < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: position, length: 0))
            let range = NSRange(location: start, length: contentsEnd - start)
            lines.append(Line(range: range, text: ns.substring(with: range)))
            position = end
        }
        return lines
    }

    /// Index of the line holding `offset`: the last one starting at or
    /// before it.
    static func lineIndex(in lines: [Line], at offset: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].range.location <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Fenced code (``` or ~~~) is left alone; a fence delimiter line
    /// itself does not qualify either.
    static func isInsideFence(_ lines: [Line], lineIndex: Int) -> Bool {
        var open: String?
        for index in 0...lineIndex {
            let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.hasPrefix("```") ? "```" : trimmed.hasPrefix("~~~") ? "~~~" : nil
            if let open_ = open {
                if marker == open_ {
                    if index == lineIndex { return true }
                    open = nil
                }
            } else if let marker {
                if index == lineIndex { return true }
                open = marker
            }
        }
        return open != nil
    }
}
