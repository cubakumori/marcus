import Foundation

/// Kind of a physical line, as relevant for editor highlighting.
public enum LineKind: Equatable, Sendable {
    case blank
    case heading(level: Int)
    case fenceDelimiter
    case fencedCode
    case indentedCode
    case blockquote
    case listItem
    case thematicBreak
    case paragraph
}

/// Kind of an inline span inside a line.
public enum InlineKind: Equatable, Sendable {
    /// Structural syntax: leading `#`, `>`, list bullets, fence delimiters, thematic breaks.
    case marker
    case code
    case emphasis
    case strong
    case linkText
    case linkURL
}

/// A styled region inside a line. `range` is relative to the line's start,
/// so unmoved lines compare equal across edits elsewhere in the document.
public struct InlineSpan: Equatable, Sendable {
    public let range: NSRange
    public let kind: InlineKind

    public init(range: NSRange, kind: InlineKind) {
        self.range = range
        self.kind = kind
    }
}

public struct ScannedLine: Equatable, Sendable {
    /// Absolute UTF-16 range of the line's content, excluding the line terminator.
    public let range: NSRange
    public let kind: LineKind
    public let spans: [InlineSpan]

    public init(range: NSRange, kind: LineKind, spans: [InlineSpan]) {
        self.range = range
        self.kind = kind
        self.spans = spans
    }

    /// Equality ignoring the line's absolute position — used to diff scans
    /// so an insertion near the top doesn't mark every following line dirty.
    public func contentEquals(_ other: ScannedLine) -> Bool {
        range.length == other.range.length && kind == other.kind && spans == other.spans
    }
}

public struct MarkdownScan: Sendable {
    public let lines: [ScannedLine]

    public init(lines: [ScannedLine]) {
        self.lines = lines
    }
}

/// Line-oriented Markdown scanner for editor highlighting.
///
/// This is deliberately not a conforming CommonMark parser: it classifies
/// physical lines and finds inline spans with simple, predictable rules.
/// Preview/export (Fase 2) will use swift-markdown instead — see ROADMAP D4/D5.
public enum MarkdownScanner {

    public static func scan(_ text: String) -> MarkdownScan {
        let u = Array(text.utf16)
        var lines: [ScannedLine] = []
        var fence: (char: UInt16, length: Int)? = nil
        var prevKind: LineKind = .blank
        var i = 0

        while true {
            var j = i
            while j < u.count, u[j] != 0x0A, u[j] != 0x0D { j += 1 }
            let line = classify(u, i..<j, fence: &fence, prevKind: prevKind)
            lines.append(line)
            prevKind = line.kind
            if j >= u.count { break }
            i = (u[j] == 0x0D && j + 1 < u.count && u[j + 1] == 0x0A) ? j + 2 : j + 1
            if i == u.count {
                // Text ends with a newline: account for the final empty line.
                lines.append(ScannedLine(range: NSRange(location: i, length: 0), kind: .blank, spans: []))
                break
            }
        }
        return MarkdownScan(lines: lines)
    }

    // MARK: - Line classification

    private static func classify(
        _ u: [UInt16],
        _ r: Range<Int>,
        fence: inout (char: UInt16, length: Int)?,
        prevKind: LineKind
    ) -> ScannedLine {
        let range = NSRange(location: r.lowerBound, length: r.count)
        func make(_ kind: LineKind, _ spans: [InlineSpan] = []) -> ScannedLine {
            ScannedLine(range: range, kind: kind, spans: spans)
        }
        func wholeLineMarker() -> [InlineSpan] {
            [InlineSpan(range: NSRange(location: 0, length: r.count), kind: .marker)]
        }

        var k = r.lowerBound
        var indent = 0
        while k < r.upperBound, u[k] == 0x20 || u[k] == 0x09 {
            indent += (u[k] == 0x09 ? 4 : 1)
            k += 1
        }
        let isBlank = k == r.upperBound

        if let open = fence {
            if !isBlank, indent <= 3 {
                var m = k, n = 0
                while m < r.upperBound, u[m] == open.char { n += 1; m += 1 }
                var rest = m
                while rest < r.upperBound, u[rest] == 0x20 || u[rest] == 0x09 { rest += 1 }
                if n >= open.length, rest == r.upperBound {
                    fence = nil
                    return make(.fenceDelimiter, wholeLineMarker())
                }
            }
            return make(.fencedCode)
        }

        if isBlank { return make(.blank) }

        if indent >= 4 {
            switch prevKind {
            case .paragraph, .blockquote, .listItem, .heading:
                // Lazy continuation of the previous block, not code.
                return make(.paragraph, inlineSpans(u, r, contentStart: k))
            default:
                return make(.indentedCode)
            }
        }

        let c = u[k]

        // Fence open: ``` or ~~~ (3+)
        if c == 0x60 || c == 0x7E {
            var m = k, n = 0
            while m < r.upperBound, u[m] == c { n += 1; m += 1 }
            if n >= 3 {
                fence = (char: c, length: n)
                return make(.fenceDelimiter, wholeLineMarker())
            }
        }

        // ATX heading: 1-6 '#' followed by space or end of line
        if c == 0x23 {
            var m = k, n = 0
            while m < r.upperBound, u[m] == 0x23 { n += 1; m += 1 }
            if n <= 6, m == r.upperBound || u[m] == 0x20 || u[m] == 0x09 {
                var spans = [InlineSpan(range: NSRange(location: k - r.lowerBound, length: n), kind: .marker)]
                spans += inlineSpans(u, r, contentStart: min(m + 1, r.upperBound))
                return make(.heading(level: n), spans)
            }
        }

        // Blockquote
        if c == 0x3E {
            var spans = [InlineSpan(range: NSRange(location: k - r.lowerBound, length: 1), kind: .marker)]
            spans += inlineSpans(u, r, contentStart: min(k + 1, r.upperBound))
            return make(.blockquote, spans)
        }

        // Thematic break: 3+ of the same char among - _ * plus spaces.
        // Checked before lists so "- - -" isn't a list item.
        do {
            var m = k
            var markerChar: UInt16? = nil
            var count = 0
            var valid = true
            while m < r.upperBound {
                let ch = u[m]
                if ch == 0x2D || ch == 0x5F || ch == 0x2A {
                    if markerChar == nil { markerChar = ch }
                    if ch != markerChar { valid = false; break }
                    count += 1
                } else if ch != 0x20, ch != 0x09 {
                    valid = false
                    break
                }
                m += 1
            }
            if valid, count >= 3 { return make(.thematicBreak, wholeLineMarker()) }
        }

        // Unordered list: - + * followed by whitespace
        if c == 0x2D || c == 0x2B || c == 0x2A,
           k + 1 < r.upperBound, u[k + 1] == 0x20 || u[k + 1] == 0x09 {
            var spans = [InlineSpan(range: NSRange(location: k - r.lowerBound, length: 1), kind: .marker)]
            spans += inlineSpans(u, r, contentStart: k + 2)
            return make(.listItem, spans)
        }

        // Ordered list: up to 9 digits, '.' or ')', whitespace
        if c >= 0x30, c <= 0x39 {
            var m = k
            while m < r.upperBound, u[m] >= 0x30, u[m] <= 0x39 { m += 1 }
            if m - k <= 9, m + 1 < r.upperBound,
               u[m] == 0x2E || u[m] == 0x29,
               u[m + 1] == 0x20 || u[m + 1] == 0x09 {
                var spans = [InlineSpan(range: NSRange(location: k - r.lowerBound, length: m - k + 1), kind: .marker)]
                spans += inlineSpans(u, r, contentStart: m + 2)
                return make(.listItem, spans)
            }
        }

        return make(.paragraph, inlineSpans(u, r, contentStart: k))
    }

    // MARK: - Inline spans

    private static func inlineSpans(_ u: [UInt16], _ r: Range<Int>, contentStart: Int) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        let base = r.lowerBound
        let start = min(max(contentStart, r.lowerBound), r.upperBound)
        let end = r.upperBound

        // 1. Code spans: a backtick run closed by a run of the same length.
        var codeRanges: [Range<Int>] = []
        var i = start
        while i < end {
            guard u[i] == 0x60 else { i += 1; continue }
            var m = i, n = 0
            while m < end, u[m] == 0x60 { n += 1; m += 1 }
            var p = m
            var closeStart = -1
            while p < end {
                if u[p] == 0x60 {
                    var q = p, cn = 0
                    while q < end, u[q] == 0x60 { cn += 1; q += 1 }
                    if cn == n { closeStart = p; break }
                    p = q
                } else {
                    p += 1
                }
            }
            if closeStart >= 0 {
                codeRanges.append(i..<(closeStart + n))
                i = closeStart + n
            } else {
                i = m
            }
        }
        for cr in codeRanges {
            spans.append(InlineSpan(range: NSRange(location: cr.lowerBound - base, length: cr.count), kind: .code))
        }
        func inCode(_ idx: Int) -> Bool { codeRanges.contains { $0.contains(idx) } }

        // 2. Links: [text](url), non-nested.
        i = start
        while i < end {
            guard u[i] == 0x5B, !inCode(i) else { i += 1; continue }
            var m = i + 1
            while m < end, u[m] != 0x5D { m += 1 }
            if m + 1 < end, u[m + 1] == 0x28 {
                var p = m + 2
                while p < end, u[p] != 0x29 { p += 1 }
                if p < end {
                    spans.append(InlineSpan(range: NSRange(location: i - base, length: m - i + 1), kind: .linkText))
                    spans.append(InlineSpan(range: NSRange(location: m + 1 - base, length: p - m), kind: .linkURL))
                    i = p + 1
                    continue
                }
            }
            i += 1
        }

        // 3. Emphasis and strong: * / _ runs. A 2+ run closed by a 2+ run is
        // strong; anything else that closes is emphasis. Not spec-exact —
        // good enough for highlighting.
        i = start
        while i < end {
            let c = u[i]
            guard c == 0x2A || c == 0x5F, !inCode(i) else { i += 1; continue }
            var m = i, n = 0
            while m < end, u[m] == c { n += 1; m += 1 }
            guard m < end, u[m] != 0x20, u[m] != 0x09 else { i = m; continue }
            var p = m
            var closeStart = -1, closeLen = 0
            while p < end {
                if u[p] == c, !inCode(p) {
                    var q = p, cn = 0
                    while q < end, u[q] == c { cn += 1; q += 1 }
                    closeStart = p
                    closeLen = cn
                    break
                }
                p += 1
            }
            if closeStart > m {
                let kind: InlineKind = (n >= 2 && closeLen >= 2) ? .strong : .emphasis
                let spanEnd = closeStart + min(closeLen, n)
                spans.append(InlineSpan(range: NSRange(location: i - base, length: spanEnd - i), kind: kind))
                i = spanEnd
            } else {
                i = m
            }
        }

        return spans.sorted { $0.range.location < $1.range.location }
    }
}
