import Foundation

/// Positional YAML front matter (Fase 7, D16): a block exists only when
/// line 1 of the text is exactly «---», and it runs to the first later line
/// that is exactly «---». No YAML parsing, no validation — the content is
/// never interpreted. Without a closer there is no block.
public enum FrontMatter {

    /// The block at the start of `text` — both delimiters and their line
    /// terminators included — or nil if there is none. Consumers that omit
    /// the block (preview, exports, Copy as HTML) drop `utf16Length` from
    /// the front and shift source line numbers by `lineCount`.
    public static func block(in text: String) -> (lineCount: Int, utf16Length: Int)? {
        block(in: Array(text.utf16))
    }

    /// Same, over the scanner's UTF-16 buffer.
    static func block(in u: [UInt16]) -> (lineCount: Int, utf16Length: Int)? {
        guard isDelimiter(u, lineStart: 0) else { return nil }
        var p = nextLineStart(u, after: 0)
        var lineCount = 1
        while p < u.count {
            lineCount += 1
            if isDelimiter(u, lineStart: p) {
                return (lineCount, nextLineStart(u, after: p))
            }
            p = nextLineStart(u, after: p)
        }
        return nil
    }

    /// Exactly three dashes up to the line terminator (or end of text).
    private static func isDelimiter(_ u: [UInt16], lineStart: Int) -> Bool {
        lineEnd(u, from: lineStart) - lineStart == 3
            && u[lineStart] == 0x2D && u[lineStart + 1] == 0x2D && u[lineStart + 2] == 0x2D
    }

    private static func lineEnd(_ u: [UInt16], from start: Int) -> Int {
        var q = start
        while q < u.count, u[q] != 0x0A, u[q] != 0x0D { q += 1 }
        return q
    }

    /// Start of the next line, past the terminator; `u.count` at the end.
    private static func nextLineStart(_ u: [UInt16], after start: Int) -> Int {
        let q = lineEnd(u, from: start)
        guard q < u.count else { return u.count }
        return (u[q] == 0x0D && q + 1 < u.count && u[q + 1] == 0x0A) ? q + 2 : q + 1
    }
}
