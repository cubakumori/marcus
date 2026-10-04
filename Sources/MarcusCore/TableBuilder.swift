import Foundation

/// Builds an empty, aligned GFM table for Format → Insert Table… (pure
/// text; the editor applies it as one undoable insertion and selects the
/// first header cell to type over).
public enum TableBuilder {

    public struct Insertion: Equatable, Sendable {
        /// What to insert at the caret, blank lines around included.
        public let replacement: String
        /// The first header cell, relative to `replacement`.
        public let selection: NSRange
    }

    /// `rows` data rows (the header is extra) by `columns`, headers named
    /// by `header(1…columns)`. Both counts are clamped to at least 1.
    public static func table(rows: Int, columns: Int, header: (Int) -> String) -> [String] {
        let rows = max(rows, 1)
        let columns = max(columns, 1)
        let headerCells = (1...columns).map(header)
        var lines = [headerCells.joined(separator: " | ")]
        lines.append((0..<columns).map { _ in "---" }.joined(separator: " | "))
        for _ in 0..<rows {
            lines.append((0..<columns).map { _ in "" }.joined(separator: " | "))
        }
        return TableFormatter.formattedLines(lines)
    }

    /// The table as text to insert at `offset`: on its own lines, with a
    /// blank line before and after unless the surroundings already supply
    /// one (a table glued to a paragraph would not be one in Markdown).
    public static func insertion(in text: String, at offset: Int, rows: Int, columns: Int,
                                 header: (Int) -> String) -> Insertion {
        let ns = text as NSString
        let offset = min(max(offset, 0), ns.length)
        let before = ns.substring(to: offset)
        let after = ns.substring(from: offset)
        let terminator = ns.range(of: "\r\n").location == NSNotFound ? "\n" : "\r\n"

        let prefix: String
        if before.isEmpty || before.hasSuffix(terminator + terminator) || before == terminator {
            prefix = ""
        } else if before.hasSuffix(terminator) {
            prefix = terminator
        } else {
            prefix = terminator + terminator
        }
        let suffix: String
        if after.isEmpty || after.hasPrefix(terminator + terminator) {
            suffix = after.isEmpty ? terminator : ""
        } else if after.hasPrefix(terminator) {
            suffix = terminator
        } else {
            suffix = terminator + terminator
        }

        let lines = table(rows: rows, columns: columns, header: header)
        let replacement = prefix + lines.joined(separator: terminator) + suffix
        // "| " then the first header cell.
        let selection = NSRange(location: (prefix as NSString).length + 2, length: (header(1) as NSString).length)
        return Insertion(replacement: replacement, selection: selection)
    }
}
