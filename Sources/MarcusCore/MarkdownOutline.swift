import Foundation

/// A heading in the document, for the outline sidebar and quick navigation.
public struct OutlineItem: Equatable, Sendable {
    public let level: Int
    public let title: String
    /// The heading line's range in the source text (navigation target).
    public let range: NSRange

    public init(level: Int, title: String, range: NSRange) {
        self.level = level
        self.title = title
        self.range = range
    }
}

/// Derives the document outline from an existing scan — no extra parsing,
/// no database, no folder indexing: in memory, per document (Fase 3).
public enum MarkdownOutline {

    public static func items(from scan: MarkdownScan, in text: String) -> [OutlineItem] {
        let ns = text as NSString
        var items: [OutlineItem] = []
        for line in scan.lines {
            guard case .heading(let level) = line.kind,
                  line.range.length > 0, NSMaxRange(line.range) <= ns.length
            else { continue }
            items.append(OutlineItem(level: level, title: title(of: line, in: ns), range: line.range))
        }
        return items
    }

    /// The heading text without its markers (leading `#`s, emphasis
    /// delimiters) or an optional ATX closing sequence. Inline code keeps
    /// its backticks — the title stays faithful to the source.
    private static func title(of line: ScannedLine, in ns: NSString) -> String {
        let lineText = ns.substring(with: line.range) as NSString
        var kept = ""
        var cursor = 0
        for span in line.spans.sorted(by: { $0.range.location < $1.range.location })
        where span.kind == .marker || span.kind == .strong || span.kind == .emphasis {
            let start = min(span.range.location, lineText.length)
            let end = min(NSMaxRange(span.range), lineText.length)
            guard start >= cursor, end > start else { continue }
            if start > cursor {
                kept += lineText.substring(with: NSRange(location: cursor, length: start - cursor))
            }
            if span.kind != .marker {
                // Emphasis spans include their * / _ delimiter runs; keep
                // only the content between them.
                let spanText = lineText.substring(with: NSRange(location: start, length: end - start))
                kept += spanText.trimmingCharacters(in: CharacterSet(charactersIn: String(spanText.first ?? " ")))
            }
            cursor = end
        }
        if cursor < lineText.length {
            kept += lineText.substring(from: cursor)
        }

        var title = Substring(kept.trimmingCharacters(in: .whitespacesAndNewlines))
        // Optional closing sequence ("## Title ##"): a trailing run of #s
        // only closes the heading when preceded by whitespace (CommonMark).
        let closingRun = title.reversed().prefix(while: { $0 == "#" }).count
        if closingRun > 0 {
            let beforeRun = title.dropLast(closingRun)
            if beforeRun.isEmpty || beforeRun.last == " " || beforeRun.last == "\t" {
                title = beforeRun
            }
        }
        return title.trimmingCharacters(in: .whitespaces)
    }
}
