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

/// An open fenced-code-block delimiter the scanner is currently inside.
struct FenceState: Equatable, Sendable {
    let char: UInt16
    let length: Int
}

/// Scanner state at the *start* of a line. Two positions with equal entry
/// states classify all following text identically, which is what lets an
/// incremental re-scan splice back into the previous scan.
struct EntryState: Equatable, Sendable {
    var fence: FenceState?
    var prevKind: LineKind

    static let initial = EntryState(fence: nil, prevKind: .blank)
}

public struct MarkdownScan: Sendable {
    public let lines: [ScannedLine]
    /// UTF-16 mirror of the scanned text, kept so the next edit can be
    /// re-scanned incrementally without touching the whole document.
    let buffer: [UInt16]
    let entryStates: [EntryState]

    /// 1-based line number of the line holding a UTF-16 offset (caret →
    /// line for the editor→preview sync). Line ranges exclude their
    /// newline, so the answer is the last line starting at or before the
    /// offset; offsets past the end map to the last line.
    public func lineNumber(at offset: Int) -> Int {
        guard !lines.isEmpty else { return 1 }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].range.location <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
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
        let (lines, states, _) = scanLines(u, from: 0, entry: .initial, resume: nil)
        return MarkdownScan(lines: lines, buffer: u, entryStates: states)
    }

    /// Re-scans after a single edit, reusing everything before the edited
    /// line and splicing back into `old` at the first position past the edit
    /// where the scanner state matches. Cost is proportional to the edit,
    /// not the document. Falls back to a full scan if the inputs are
    /// inconsistent with `old`.
    ///
    /// - Parameters:
    ///   - editedRange: range of the replacement in the *new* text.
    ///   - delta: length change (new length − old length).
    /// - Returns: the new scan plus the indices of lines that need restyling.
    ///   Lines after the splice point moved, but their attributes moved with
    ///   the text, so they are not reported dirty.
    public static func rescan(
        after old: MarkdownScan,
        editedRange: NSRange,
        delta: Int,
        in text: String
    ) -> (scan: MarkdownScan, dirtyLines: Range<Int>) {
        let ns = text as NSString
        let replacedLength = editedRange.length - delta
        guard editedRange.location >= 0,
              replacedLength >= 0,
              editedRange.location + replacedLength <= old.buffer.count,
              NSMaxRange(editedRange) <= ns.length,
              old.buffer.count + delta == ns.length,
              !old.lines.isEmpty
        else {
            let full = scan(text)
            return (full, 0..<full.lines.count)
        }

        var u = old.buffer
        var inserted = [UInt16](repeating: 0, count: editedRange.length)
        if editedRange.length > 0 { ns.getCharacters(&inserted, range: editedRange) }
        u.replaceSubrange(editedRange.location..<(editedRange.location + replacedLength), with: inserted)

        // Last line starting at or before the edit; everything before it is untouched.
        var lo = 0, hi = old.lines.count - 1, startLine = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if old.lines[mid].range.location <= editedRange.location {
                startLine = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        let context = ResumeContext(old: old, delta: delta, editedEnd: NSMaxRange(editedRange), j: startLine)
        let (scanned, scannedStates, resumedAt) = scanLines(
            u,
            from: old.lines[startLine].range.location,
            entry: old.entryStates[startLine],
            resume: context
        )

        var lines = Array(old.lines[0..<startLine])
        var states = Array(old.entryStates[0..<startLine])
        lines += scanned
        states += scannedStates
        let dirty = startLine..<lines.count
        if let j = resumedAt {
            for index in j..<old.lines.count {
                let line = old.lines[index]
                lines.append(ScannedLine(
                    range: NSRange(location: line.range.location + delta, length: line.range.length),
                    kind: line.kind,
                    spans: line.spans
                ))
            }
            states += old.entryStates[j...]
        }
        return (MarkdownScan(lines: lines, buffer: u, entryStates: states), dirty)
    }

    // MARK: - Line iteration

    private struct ResumeContext {
        let old: MarkdownScan
        let delta: Int
        /// End of the edited range in new-text coordinates; no splicing
        /// before this point.
        let editedEnd: Int
        /// Monotonic pointer into `old.lines` for splice candidates.
        var j: Int
    }

    /// Scans lines of `u` starting at line-start `p0`. With a resume context,
    /// stops as soon as a line start maps onto an old line start with an
    /// identical entry state and returns that old index for splicing.
    private static func scanLines(
        _ u: [UInt16],
        from p0: Int,
        entry: EntryState,
        resume: ResumeContext?
    ) -> (lines: [ScannedLine], states: [EntryState], resumedAtOldIndex: Int?) {
        var lines: [ScannedLine] = []
        var states: [EntryState] = []
        var state = entry
        var p = p0
        var context = resume

        while true {
            if var c = context, p >= c.editedEnd {
                while c.j < c.old.lines.count, c.old.lines[c.j].range.location < p - c.delta { c.j += 1 }
                if c.j < c.old.lines.count,
                   c.old.lines[c.j].range.location == p - c.delta,
                   c.old.entryStates[c.j] == state {
                    return (lines, states, c.j)
                }
                context = c
            }

            var q = p
            while q < u.count, u[q] != 0x0A, u[q] != 0x0D { q += 1 }
            states.append(state)
            let line = classify(u, p..<q, state: &state)
            lines.append(line)
            state.prevKind = line.kind
            if q >= u.count { break }
            p = (u[q] == 0x0D && q + 1 < u.count && u[q + 1] == 0x0A) ? q + 2 : q + 1
            if p == u.count {
                // Text ends with a newline: account for the final empty line.
                states.append(state)
                lines.append(ScannedLine(range: NSRange(location: p, length: 0), kind: .blank, spans: []))
                break
            }
        }
        return (lines, states, nil)
    }

    // MARK: - Line classification

    private static func classify(_ u: [UInt16], _ r: Range<Int>, state: inout EntryState) -> ScannedLine {
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

        if let open = state.fence {
            if !isBlank, indent <= 3 {
                var m = k, n = 0
                while m < r.upperBound, u[m] == open.char { n += 1; m += 1 }
                var rest = m
                while rest < r.upperBound, u[rest] == 0x20 || u[rest] == 0x09 { rest += 1 }
                if n >= open.length, rest == r.upperBound {
                    state.fence = nil
                    return make(.fenceDelimiter, wholeLineMarker())
                }
            }
            return make(.fencedCode)
        }

        if isBlank { return make(.blank) }

        if indent >= 4 {
            switch state.prevKind {
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
                state.fence = FenceState(char: c, length: n)
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

        // 3. Emphasis and strong: * and _ runs. A 2+ run closed by a 2+ run is
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
