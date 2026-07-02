import AppKit
import MarcusCore

/// Applies theme attributes to an NSTextStorage from a MarkdownScan.
/// Incremental: after each edit the document is re-scanned (a cheap single
/// pass) but attributes are only re-applied to lines whose content changed —
/// including lines far from the edit whose kind flipped (e.g. a fence toggled).
@MainActor
final class MarkdownHighlighter {

    let theme = MarkdownTheme()
    private var lastScan: MarkdownScan?

    func highlightAll(_ storage: NSTextStorage) {
        let scan = MarkdownScanner.scan(storage.string)
        apply(scan: scan, lineIndices: Array(scan.lines.indices), to: storage)
        lastScan = scan
    }

    func highlightAfterEdit(_ storage: NSTextStorage) {
        guard let old = lastScan else {
            highlightAll(storage)
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
            for span in line.spans {
                let absolute = NSRange(location: line.range.location + span.range.location, length: span.range.length)
                guard NSMaxRange(absolute) <= NSMaxRange(line.range) else { continue }
                storage.addAttributes(theme.attributes(for: span.kind, in: line.kind), range: absolute)
            }
        }
        storage.endEditing()
    }
}

@MainActor
final class MarkdownTheme {

    let bodySize: CGFloat = 14

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
            .foregroundColor: NSColor.labelColor,
        ]
        switch kind {
        case .heading(let level):
            attrs[.font] = headingFont(level: level)
        case .fencedCode, .indentedCode:
            attrs[.backgroundColor] = NSColor.quaternarySystemFill
        case .fenceDelimiter:
            attrs[.foregroundColor] = NSColor.tertiaryLabelColor
            attrs[.backgroundColor] = NSColor.quaternarySystemFill
        case .blockquote:
            attrs[.foregroundColor] = NSColor.secondaryLabelColor
        case .thematicBreak:
            attrs[.foregroundColor] = NSColor.tertiaryLabelColor
        case .blank, .paragraph, .listItem:
            break
        }
        return attrs
    }

    func attributes(for kind: InlineKind, in lineKind: LineKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .marker:
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.tertiaryLabelColor]
            if case .listItem = lineKind {
                attrs[.foregroundColor] = NSColor.controlAccentColor
            }
            return attrs
        case .code:
            return [
                .foregroundColor: NSColor.systemPurple,
                .backgroundColor: NSColor.quaternarySystemFill,
            ]
        case .strong:
            return [.font: emphasized(baseFont(for: lineKind), bold: true)]
        case .emphasis:
            return [.font: emphasized(baseFont(for: lineKind), bold: false), .obliqueness: 0.13]
        case .linkText:
            return [.foregroundColor: NSColor.linkColor]
        case .linkURL:
            return [.foregroundColor: NSColor.secondaryLabelColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
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
