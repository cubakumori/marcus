import AppKit
import Markdown
import MarcusCore

/// Wrapper to move an immutable rendered string across concurrency domains.
/// NSAttributedString is immutable; the attachments it carries are only read.
public struct RenderedPreview: @unchecked Sendable {
    public let string: NSAttributedString
    /// Heading anchors in document order, for the editor→preview sync.
    public let anchors: [PreviewAnchor]
}

extension NSAttributedString.Key {
    /// 1-based source line carried by rendered headings; harvested into
    /// `RenderedPreview.anchors` after the build.
    static let marcusSourceLine = NSAttributedString.Key("MarcusSourceLine")
}

/// Ink colors for the rendered preview. Defaults to the system's semantic
/// colors; the app passes the editor theme's palette so the preview matches
/// it. NSColor is immutable and safe to read across threads.
public struct PreviewPalette: @unchecked Sendable {
    public var text: NSColor
    public var secondaryText: NSColor
    public var tertiaryText: NSColor
    public var link: NSColor
    public var code: NSColor
    public var codeBackground: NSColor

    public init(
        text: NSColor = .labelColor,
        secondaryText: NSColor = .secondaryLabelColor,
        tertiaryText: NSColor = .tertiaryLabelColor,
        link: NSColor = .linkColor,
        code: NSColor = .systemPurple,
        codeBackground: NSColor = .quaternarySystemFill
    ) {
        self.text = text
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.link = link
        self.code = code
        self.codeBackground = codeBackground
    }
}

public struct PreviewRenderOptions: Sendable {
    /// Base for resolving relative image paths and links (usually the
    /// document's folder).
    public var baseURL: URL?
    /// Ink colors; the view's background is the caller's responsibility.
    public var palette: PreviewPalette

    public init(baseURL: URL? = nil, palette: PreviewPalette = .init()) {
        self.baseURL = baseURL
        self.palette = palette
    }
}

/// Renders Markdown into an NSAttributedString with reading typography.
/// Designed to run off the main thread: parse + build happen wherever the
/// caller wants; only displaying the result touches the UI.
public enum MarkdownPreviewRenderer {

    public static func render(_ markdown: String, options: PreviewRenderOptions = .init()) -> RenderedPreview {
        // Front matter (Fase 7, D16) is metadata, not document: dropped
        // before parsing. Anchors keep full-document line numbers — the
        // editor→preview sync works in those.
        var text = markdown
        var lineOffset = 0
        if let block = FrontMatter.block(in: markdown) {
            text = (markdown as NSString).substring(from: block.utf16Length)
            lineOffset = block.lineCount
        }
        let document = Document(parsing: text)
        var visitor = AttributedStringVisitor(options: options)
        let string = visitor.visit(document)
        return RenderedPreview(string: string, anchors: anchors(in: string, lineOffset: lineOffset))
    }

    private static func anchors(in string: NSAttributedString, lineOffset: Int) -> [PreviewAnchor] {
        var anchors: [PreviewAnchor] = []
        string.enumerateAttribute(.marcusSourceLine, in: NSRange(location: 0, length: string.length)) { value, range, _ in
            guard let line = value as? Int else { return }
            anchors.append(PreviewAnchor(sourceLine: line + lineOffset, location: range.location))
        }
        return anchors
    }
}

// MARK: - Theme

struct PreviewTheme {
    let palette: PreviewPalette
    let bodyFont = NSFont.systemFont(ofSize: 15)
    let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func headingFont(level: Int) -> NSFont {
        let sizes: [CGFloat] = [28, 23, 19, 17, 15, 14]
        return NSFont.systemFont(ofSize: sizes[max(0, min(level, 6) - 1)], weight: .semibold)
    }

    var body: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.25
        style.paragraphSpacing = 10
        return style
    }

    func heading(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = level <= 2 ? 18 : 12
        style.paragraphSpacing = 8
        return style
    }

    var codeBlock: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.paragraphSpacing = 10
        style.lineHeightMultiple = 1.15
        return style
    }

    func indented(depth: Int, hanging: CGFloat = 16) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = CGFloat(depth) * 22
        style.firstLineHeadIndent = indent
        style.headIndent = indent + hanging
        style.lineHeightMultiple = 1.25
        style.paragraphSpacing = 4
        return style
    }
}

// MARK: - Visitor

private struct AttributedStringVisitor: MarkupVisitor {
    typealias Result = NSAttributedString

    let options: PreviewRenderOptions
    let theme: PreviewTheme

    // Inline state, pushed/popped around children visits.
    private var font: NSFont
    private var color: NSColor

    init(options: PreviewRenderOptions) {
        self.options = options
        let theme = PreviewTheme(palette: options.palette)
        self.theme = theme
        self.font = theme.bodyFont
        self.color = options.palette.text
    }

    // MARK: Helpers

    private mutating func children(of markup: Markup) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children { out.append(visit(child)) }
        return out
    }

    private func inlineAttributes() -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    private func block(_ content: NSAttributedString, style: NSParagraphStyle) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: content)
        out.append(NSAttributedString(string: "\n", attributes: inlineAttributes()))
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return out
    }

    private func withFont<T>(_ newFont: NSFont, _ body: (inout Self) -> T) -> T {
        var copy = self
        copy.font = newFont
        return body(&copy)
    }

    private var italicFont: NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private var boldFont: NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private func plainString(of markup: Markup) -> String {
        var out = ""
        for child in markup.children {
            switch child {
            case let text as Text: out += text.string
            case let code as InlineCode: out += code.code
            case is SoftBreak, is LineBreak: out += " "
            default: out += plainString(of: child)
            }
        }
        if let text = markup as? Text { out += text.string }
        return out
    }

    // MARK: Blocks

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        children(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> NSAttributedString {
        children(of: document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        block(children(of: paragraph), style: theme.body)
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        var visitor = self
        visitor.font = theme.headingFont(level: heading.level)
        let content = visitor.children(of: heading)
        let out = NSMutableAttributedString(attributedString: block(content, style: theme.heading(level: heading.level)))
        if let line = heading.range?.lowerBound.line {
            out.addAttribute(.marcusSourceLine, value: line, range: NSRange(location: 0, length: out.length))
        }
        return out
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        if code.hasSuffix("\n") { code.removeLast() }
        let content = NSAttributedString(string: code, attributes: [
            .font: theme.monoFont,
            .foregroundColor: theme.palette.text,
            .backgroundColor: theme.palette.codeBackground,
        ])
        return block(content, style: theme.codeBlock)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        var visitor = self
        visitor.color = theme.palette.secondaryText
        let content = NSMutableAttributedString(attributedString: visitor.children(of: blockQuote))
        content.addAttribute(.paragraphStyle, value: theme.indented(depth: 1, hanging: 0),
                             range: NSRange(location: 0, length: content.length))
        return content
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let line = NSAttributedString(string: String(repeating: "─", count: 30), attributes: [
            .font: theme.bodyFont,
            .foregroundColor: theme.palette.tertiaryText,
        ])
        return block(line, style: theme.body)
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> NSAttributedString {
        list(unorderedList, marker: { item, _ in
            switch item.checkbox {
            case .checked: "☑ "
            case .unchecked: "☐ "
            case nil: "•  "
            }
        })
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> NSAttributedString {
        let start = Int(orderedList.startIndex)
        return list(orderedList, marker: { _, index in "\(start + index).  " })
    }

    private mutating func list(_ listMarkup: Markup, marker: (ListItem, Int) -> String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, child) in listMarkup.children.enumerated() {
            guard let item = child as? ListItem else { continue }
            let content = NSMutableAttributedString()
            content.append(NSAttributedString(string: marker(item, index), attributes: inlineAttributes()))
            content.append(children(of: item))
            if !content.string.hasSuffix("\n") {
                content.append(NSAttributedString(string: "\n", attributes: inlineAttributes()))
            }
            content.addAttribute(.paragraphStyle, value: theme.indented(depth: 1),
                                 range: NSRange(location: 0, length: content.length))
            out.append(content)
        }
        return out
    }

    mutating func visitListItem(_ listItem: ListItem) -> NSAttributedString {
        // Children of a list item are paragraphs; render them inline without
        // the paragraph block spacing so the item stays compact.
        let out = NSMutableAttributedString()
        for (index, child) in listItem.children.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n", attributes: inlineAttributes())) }
            if let paragraph = child as? Paragraph {
                out.append(children(of: paragraph))
            } else {
                out.append(visit(child))
            }
        }
        return out
    }

    mutating func visitTable(_ table: Table) -> NSAttributedString {
        // v1: monospaced grid. TextKit 2 has no native table layout; a richer
        // rendering can come later without touching the pipeline.
        var rows: [[String]] = []
        rows.append(table.head.cells.map { plainString(of: $0) })
        for row in table.body.rows {
            rows.append(row.cells.map { plainString(of: $0) })
        }
        let columns = rows.map(\.count).max() ?? 0
        var widths = [Int](repeating: 0, count: columns)
        for row in rows {
            for (i, cell) in row.enumerated() { widths[i] = max(widths[i], cell.count) }
        }
        var text = ""
        for (rowIndex, row) in rows.enumerated() {
            let padded = row.enumerated().map { $0.element.padding(toLength: widths[$0.offset], withPad: " ", startingAt: 0) }
            text += padded.joined(separator: "  ") + "\n"
            if rowIndex == 0 {
                text += widths.map { String(repeating: "─", count: $0) }.joined(separator: "  ") + "\n"
            }
        }
        let content = NSAttributedString(string: String(text.dropLast()), attributes: [
            .font: theme.monoFont,
            .foregroundColor: theme.palette.text,
        ])
        return block(content, style: theme.codeBlock)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        let content = NSAttributedString(string: html.rawHTML.trimmingCharacters(in: .newlines), attributes: [
            .font: theme.monoFont,
            .foregroundColor: theme.palette.secondaryText,
        ])
        return block(content, style: theme.codeBlock)
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> NSAttributedString {
        NSAttributedString(string: text.string, attributes: inlineAttributes())
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: inlineAttributes())
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: inlineAttributes())
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        withFont(italicFont) { $0.children(of: emphasis) }
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        withFont(boldFont) { $0.children(of: strong) }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        NSAttributedString(string: inlineCode.code, attributes: [
            .font: theme.monoFont,
            .foregroundColor: theme.palette.code,
            .backgroundColor: theme.palette.codeBackground,
        ])
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: children(of: strikethrough))
        out.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                         range: NSRange(location: 0, length: out.length))
        return out
    }

    mutating func visitLink(_ link: Link) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: children(of: link))
        if let destination = link.destination,
           let url = URL(string: destination, relativeTo: options.baseURL) {
            out.addAttributes([
                .link: url,
                .foregroundColor: theme.palette.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: NSRange(location: 0, length: out.length))
        }
        return out
    }

    mutating func visitImage(_ image: Image) -> NSAttributedString {
        guard let source = image.source,
              let url = URL(string: source, relativeTo: options.baseURL),
              url.isFileURL,
              let loaded = NSImage(contentsOf: url)
        else {
            return NSAttributedString(string: "[\(image.source ?? String(localized: "image", bundle: .module))]", attributes: [
                .font: theme.bodyFont,
                .foregroundColor: theme.palette.secondaryText,
            ])
        }
        let attachment = NSTextAttachment()
        attachment.image = loaded
        let maxWidth: CGFloat = 620
        var size = loaded.size
        if size.width > maxWidth {
            size = NSSize(width: maxWidth, height: size.height * maxWidth / size.width)
        }
        attachment.bounds = NSRect(origin: .zero, size: size)
        return NSAttributedString(attachment: attachment)
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        NSAttributedString(string: inlineHTML.rawHTML, attributes: [
            .font: theme.monoFont,
            .foregroundColor: theme.palette.secondaryText,
        ])
    }
}
