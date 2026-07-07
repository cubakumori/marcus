import AppKit
import MarcusCore

extension NSAttributedString.Key {
    /// Raw destination of a Markdown link, applied to both the [text] and
    /// (url) spans. The editor opens it on ⌘-click; nothing else reads it.
    static let marcusLinkTarget = NSAttributedString.Key("MarcusLinkTarget")
}

/// Applies theme attributes to an NSTextStorage from a MarkdownScan.
/// Incremental: after each edit the document is re-scanned (a cheap single
/// pass) but attributes are only re-applied to lines whose content changed —
/// including lines far from the edit whose kind flipped (e.g. a fence toggled).
@MainActor
final class MarkdownHighlighter {

    let theme = MarkdownTheme()
    /// Latest scan, kept fresh by every edit; the outline derives from it.
    private(set) var lastScan: MarkdownScan?
    private var pendingEdit: (range: NSRange, delta: Int)?
    private var pendingIsCompound = false

    /// Called (via NSTextStorageDelegate) for every character edit, before
    /// textDidChange triggers the re-highlight. A single recorded edit takes
    /// the incremental path; several edits in one change group (e.g.
    /// replace-all) fall back to the diff path.
    func noteEdit(range: NSRange, delta: Int) {
        if pendingEdit == nil, !pendingIsCompound {
            pendingEdit = (range, delta)
        } else {
            pendingEdit = nil
            pendingIsCompound = true
        }
    }

    private func clearPending() {
        pendingEdit = nil
        pendingIsCompound = false
    }

    func highlightAll(_ storage: NSTextStorage) {
        let scan = MarkdownScanner.scan(storage.string)
        apply(scan: scan, lineIndices: Array(scan.lines.indices), to: storage)
        lastScan = scan
        clearPending()
    }

    /// Honest plain text (Fase 6): the theme's body attributes on the whole
    /// document, no Markdown styling. Edits need no follow-up pass — typed
    /// and pasted text take the typing attributes (the editor is not rich
    /// text) — so there is no plain counterpart to highlightAfterEdit.
    func applyPlain(_ storage: NSTextStorage) {
        storage.beginEditing()
        storage.setAttributes(theme.typingAttributes,
                              range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        lastScan = nil
        clearPending()
    }

    func highlightAfterEdit(_ storage: NSTextStorage) {
        defer { clearPending() }
        guard let old = lastScan else {
            highlightAll(storage)
            return
        }

        if let edit = pendingEdit {
            let (scan, dirty) = MarkdownScanner.rescan(after: old, editedRange: edit.range, delta: edit.delta, in: storage.string)
            apply(scan: scan, lineIndices: Array(dirty), to: storage)
            lastScan = scan
            return
        }

        let scan = MarkdownScanner.scan(storage.string)
        let newLines = scan.lines
        let oldLines = old.lines

        var prefix = 0
        while prefix < newLines.count, prefix < oldLines.count,
              newLines[prefix].contentEquals(oldLines[prefix]) {
            prefix += 1
        }
        var suffix = 0
        while suffix < newLines.count - prefix, suffix < oldLines.count - prefix,
              newLines[newLines.count - 1 - suffix].contentEquals(oldLines[oldLines.count - 1 - suffix]) {
            suffix += 1
        }
        // Suffix lines kept their content but may have moved; their attributes
        // moved with the text, so only the middle needs re-applying.
        apply(scan: scan, lineIndices: Array(prefix..<(newLines.count - suffix)), to: storage)
        lastScan = scan
    }

    private func apply(scan: MarkdownScan, lineIndices: [Int], to storage: NSTextStorage) {
        guard !lineIndices.isEmpty else {
            return
        }
        storage.beginEditing()
        for index in lineIndices {
            let line = scan.lines[index]
            guard line.range.length > 0, NSMaxRange(line.range) <= storage.length else { continue }
            storage.setAttributes(theme.attributes(for: line.kind), range: line.range)
            var pendingLinkText: NSRange?
            for span in line.spans {
                let absolute = NSRange(location: line.range.location + span.range.location, length: span.range.length)
                guard NSMaxRange(absolute) <= NSMaxRange(line.range) else { continue }
                storage.addAttributes(theme.attributes(for: span.kind, in: line.kind), range: absolute)
                switch span.kind {
                case .linkText:
                    pendingLinkText = absolute
                case .linkURL:
                    // Span covers "(url" — drop the paren, keep the target.
                    let raw = (storage.string as NSString).substring(with: absolute)
                    let target = raw.hasPrefix("(") ? String(raw.dropFirst()) : raw
                    guard !target.isEmpty else { pendingLinkText = nil; break }
                    storage.addAttribute(.marcusLinkTarget, value: target, range: absolute)
                    if let textRange = pendingLinkText, NSMaxRange(textRange) == absolute.location {
                        storage.addAttribute(.marcusLinkTarget, value: target, range: textRange)
                    }
                    pendingLinkText = nil
                default:
                    break
                }
            }
        }
        storage.endEditing()
    }
}

@MainActor
final class MarkdownTheme {

    let bodySize: CGFloat = 14

    /// Active palette; the editor re-applies highlighting when it changes.
    var palette = EditorTheme.current.palette

    private lazy var bodyFont = NSFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)

    private func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [24, 21, 18, 16, 15, 14]
        let size = sizes[max(0, min(level, 6) - 1)]
        return NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    var typingAttributes: [NSAttributedString.Key: Any] { attributes(for: .paragraph) }

    func attributes(for kind: LineKind) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: palette.text,
        ]
        switch kind {
        case .heading(let level):
            attrs[.font] = headingFont(level: level)
        case .fencedCode, .indentedCode:
            attrs[.backgroundColor] = palette.codeBackground
        case .fenceDelimiter:
            attrs[.foregroundColor] = palette.tertiaryText
            attrs[.backgroundColor] = palette.codeBackground
        case .blockquote:
            attrs[.foregroundColor] = palette.secondaryText
        case .thematicBreak:
            attrs[.foregroundColor] = palette.tertiaryText
        case .blank, .paragraph, .listItem:
            break
        }
        return attrs
    }

    func attributes(for kind: InlineKind, in lineKind: LineKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .marker:
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: palette.tertiaryText]
            if case .listItem = lineKind {
                attrs[.foregroundColor] = palette.accent
            }
            return attrs
        case .code:
            return [
                .foregroundColor: palette.code,
                .backgroundColor: palette.codeBackground,
            ]
        case .strong:
            return [.font: emphasized(baseFont(for: lineKind), bold: true)]
        case .emphasis:
            return [.font: emphasized(baseFont(for: lineKind), bold: false), .obliqueness: 0.13]
        case .linkText:
            return [.foregroundColor: palette.link]
        case .linkURL:
            return [.foregroundColor: palette.secondaryText, .underlineStyle: NSUnderlineStyle.single.rawValue]
        }
    }

    private func baseFont(for lineKind: LineKind) -> NSFont {
        if case .heading(let level) = lineKind { return headingFont(level: level) }
        return bodyFont
    }

    private func emphasized(_ font: NSFont, bold: Bool) -> NSFont {
        guard bold else { return font }
        return NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
    }
}
