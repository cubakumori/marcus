import Foundation
import Markdown
import MarcusCore

public struct HTMLExportOptions: Sendable {
    /// Document title for the `<title>` element (usually the file name).
    public var title: String
    /// Base for resolving relative image paths. Local images are embedded
    /// as data URIs so the exported file is self-contained.
    public var baseURL: URL?

    public init(title: String = "Untitled", baseURL: URL? = nil) {
        self.title = title
        self.baseURL = baseURL
    }
}

/// Exports Markdown as a single self-contained HTML file: minimal template,
/// embedded CSS (light/dark via `prefers-color-scheme`), local images inlined
/// as data URIs. No scripts, no external resources.
public enum MarkdownHTMLExporter {

    /// Complete HTML document ready to write to disk.
    public static func document(from markdown: String, options: HTMLExportOptions = .init()) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(options.title))</title>
        <style>
        \(stylesheet)
        </style>
        </head>
        <body>
        \(body(from: markdown, options: options))</body>
        </html>
        """
    }

    /// Just the rendered `<body>` fragment. Also the input for PDF export,
    /// print and Copy as HTML.
    public static func body(from markdown: String, options: HTMLExportOptions = .init()) -> String {
        // Front matter (Fase 7, D16) is metadata, not document: dropped here
        // so every HTML consumer omits it through the same door.
        var text = markdown
        if let block = FrontMatter.block(in: markdown) {
            text = (markdown as NSString).substring(from: block.utf16Length)
        }
        var visitor = HTMLVisitor(options: options)
        return visitor.visit(Document(parsing: text))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let stylesheet = """
    :root { color-scheme: light dark; }
    body {
      font: 16px/1.6 -apple-system, system-ui, sans-serif;
      max-width: 44em; margin: 0 auto; padding: 2em 1.5em;
      color: #1d1d1f; background: #ffffff;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.4em 0 0.5em; }
    h1 { font-size: 1.9em; } h2 { font-size: 1.5em; } h3 { font-size: 1.2em; }
    pre, code { font: 0.9em ui-monospace, SF Mono, Menlo, monospace; background: #f2f2f4; border-radius: 4px; }
    code { padding: 0.15em 0.35em; }
    pre { padding: 0.8em 1em; overflow-x: auto; }
    pre code { padding: 0; background: none; }
    blockquote { margin: 0; padding-left: 1em; border-left: 3px solid #d2d2d7; color: #6e6e73; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #d2d2d7; padding: 0.35em 0.7em; }
    img { max-width: 100%; }
    hr { border: none; border-top: 1px solid #d2d2d7; margin: 2em 0; }
    a { color: #0066cc; }
    li.task { list-style: none; margin-left: -1.3em; }
    @media print {
      body { max-width: none; padding: 0; }
      pre { white-space: pre-wrap; word-break: break-word; }
    }
    @media (prefers-color-scheme: dark) {
      body { color: #f5f5f7; background: #1d1d1f; }
      pre, code { background: #2c2c2e; }
      blockquote { border-left-color: #48484a; color: #98989d; }
      th, td { border-color: #48484a; }
      hr { border-top-color: #48484a; }
      a { color: #2997ff; }
    }
    """
}

// MARK: - Visitor

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    let options: HTMLExportOptions

    private func escape(_ text: String) -> String { MarkdownHTMLExporter.escape(text) }
    private func attr(_ text: String) -> String { MarkdownHTMLExporter.escapeAttribute(text) }

    private mutating func children(of markup: Markup) -> String {
        markup.children.map { visit($0) }.joined()
    }

    // MARK: Blocks

    mutating func defaultVisit(_ markup: Markup) -> String {
        children(of: markup)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(children(of: paragraph))</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        "<h\(heading.level)>\(children(of: heading))</h\(heading.level)>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let language = codeBlock.language.map { " class=\"language-\(attr($0))\"" } ?? ""
        return "<pre><code\(language)>\(escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(children(of: blockQuote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        "<ul>\n\(children(of: unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex == 1 ? "" : " start=\"\(orderedList.startIndex)\""
        return "<ol\(start)>\n\(children(of: orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        let checkbox = switch listItem.checkbox {
        case .checked: "<input type=\"checkbox\" checked disabled> "
        case .unchecked: "<input type=\"checkbox\" disabled> "
        case nil: ""
        }
        // A single-paragraph item reads better without the <p> wrapper.
        let content: String
        if listItem.childCount == 1, let paragraph = listItem.child(at: 0) as? Paragraph {
            content = children(of: paragraph)
        } else {
            content = "\n" + children(of: listItem)
        }
        let cssClass = checkbox.isEmpty ? "" : " class=\"task\""
        return "<li\(cssClass)>\(checkbox)\(content)</li>\n"
    }

    mutating func visitTable(_ table: Table) -> String {
        let alignments = table.columnAlignments
        func style(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            let value = switch alignment {
            case .left: "left"
            case .center: "center"
            case .right: "right"
            }
            return " style=\"text-align: \(value)\""
        }
        func row(_ cells: some Sequence<Table.Cell>, tag: String) -> String {
            var out = "<tr>"
            for (column, cell) in cells.enumerated() {
                out += "<\(tag)\(style(column))>\(children(of: cell))</\(tag)>"
            }
            return out + "</tr>\n"
        }
        var out = "<table>\n<thead>\n" + row(table.head.cells, tag: "th") + "</thead>\n<tbody>\n"
        for bodyRow in table.body.rows {
            out += row(bodyRow.cells, tag: "td")
        }
        return out + "</tbody></table>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> String {
        escape(text.string)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(children(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(children(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(children(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escape(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        guard let destination = link.destination else { return children(of: link) }
        return "<a href=\"\(attr(destination))\">\(children(of: link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let alt = image.plainText
        let source = image.source ?? ""
        return "<img src=\"\(attr(embeddedSource(source) ?? source))\" alt=\"\(attr(alt))\">"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    /// Local images become data URIs so the export has no loose parts.
    private func embeddedSource(_ source: String) -> String? {
        guard let url = URL(string: source, relativeTo: options.baseURL),
              url.isFileURL,
              let mimeType = Self.mimeTypes[url.pathExtension.lowercased()],
              let data = try? Data(contentsOf: url)
        else { return nil }
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp",
        "heic": "image/heic", "tiff": "image/tiff", "bmp": "image/bmp",
    ]
}
