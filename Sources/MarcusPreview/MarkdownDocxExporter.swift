import AppKit
import ImageIO
import Markdown
import MarcusCore

public struct DocxExportOptions: Sendable {
    /// Document title for the properties (Word's File → Properties). A
    /// `title:` line in the front matter wins over it.
    public var title: String
    /// Base for resolving relative image paths. Local images are embedded
    /// in the package so the exported file is self-contained.
    public var baseURL: URL?

    public init(title: String = "Untitled", baseURL: URL? = nil) {
        self.title = title
        self.baseURL = baseURL
    }
}

/// The unzipped `.docx`: every part by its path inside the package. Tests
/// read the XML here; `data` is what goes to disk.
public struct DocxPackage: Sendable {
    public var parts: [(path: String, data: Data)]

    public func part(_ path: String) -> Data? {
        parts.first { $0.path == path }?.data
    }

    public func xml(_ path: String) -> String? {
        part(path).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The zipped package, ready to write.
    public var data: Data {
        ZipArchiveWriter.archive(parts.map { ZipArchiveWriter.Entry(path: $0.path, data: $0.data) })
    }
}

/// Exports Markdown as a Word document (`.docx`) written by hand from the
/// `swift-markdown` AST — the same door as `MarkdownHTMLExporter`, not the
/// `NSAttributedString` (AppKit's `.officeOpenXML` writer drops links,
/// images and the code background; measured, see ROADMAP).
///
/// What travels: Word's own named styles (Heading 1…6, Quote, List
/// Paragraph, Hyperlink), so the navigation pane and a table of contents
/// work; real hyperlinks; images embedded in `word/media`; bullet,
/// numbered and task lists as Word numbering; GFM tables with a repeating
/// header row; code as a monospaced shaded style. Fixed paper look, like
/// the RTF: the editor theme, zoom and Dynamic Type stay in the app.
public enum MarkdownDocxExporter {

    /// `.docx` bytes ready to write to disk.
    public static func data(from markdown: String, options: DocxExportOptions = .init()) -> Data {
        package(from: markdown, options: options).data
    }

    /// The package before zipping — what the tests look at.
    public static func package(from markdown: String, options: DocxExportOptions = .init()) -> DocxPackage {
        var text = markdown
        var title = options.title
        if let block = FrontMatter.block(in: markdown) {
            text = (markdown as NSString).substring(from: block.utf16Length)
            if let frontTitle = FrontMatter.title(in: markdown) { title = frontTitle }
        }
        let writer = DocxWriter(options: options)
        writer.render(Document(parsing: text))
        return writer.package(title: title)
    }

    // MARK: - XML helpers

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            // Control characters are not representable in XML 1.0; Word
            // refuses the whole file over one of them.
            case "\u{0}"..."\u{8}", "\u{B}", "\u{C}", "\u{E}"..."\u{1F}": continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

// MARK: - Page geometry

/// Twips (1/20 pt) and EMUs (English Metric Units, 1/12700 pt) are what
/// OOXML measures in.
private enum Page {
    static let margin = 1440                      // 1 inch
    /// Letter in the US, A4 elsewhere — what the printer in that country
    /// has loaded.
    static var isLetter: Bool {
        Locale.current.measurementSystem == .us
    }
    static var width: Int { isLetter ? 12240 : 11906 }
    static var height: Int { isLetter ? 15840 : 16838 }
    static var textWidth: Int { width - 2 * margin }
    static var textWidthPoints: CGFloat { CGFloat(textWidth) / 20 }
    static let emuPerPoint: CGFloat = 12700
}

// MARK: - Writer

private struct RunStyle {
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link = false
    /// Raw HTML, kept as gray monospaced text like the preview does.
    var html = false
}

private struct BlockContext {
    var quoteDepth = 0
    /// Numbering level (`ilvl`) of the enclosing list; -1 outside lists.
    var listLevel = -1
    /// Consumed by the first paragraph of a list item, which carries the
    /// bullet or number.
    var pendingNumber: (numId: Int, level: Int)?
    /// Table cell alignment, applied to every paragraph inside.
    var alignment: String?

    var inList: Bool { listLevel >= 0 }
    /// Left indent for paragraphs that are not themselves numbered.
    var indent: Int {
        360 * quoteDepth + (inList ? 720 * (listLevel + 1) : 0)
    }
}

private struct ParagraphProperties {
    var style: String?
    var numbering: (numId: Int, level: Int)?
    var indentLeft: Int?
    var hanging: Int?
    var alignment: String?
    var spacingAfter: Int?
    var spacingBefore: Int?
    var extra = ""
    var hasContent: Bool {
        style != nil || numbering != nil || indentLeft != nil || alignment != nil
            || spacingAfter != nil || spacingBefore != nil || !extra.isEmpty
    }

    var xml: String {
        guard hasContent else { return "" }
        var out = "<w:pPr>"
        if let style { out += "<w:pStyle w:val=\"\(style)\"/>" }
        if let numbering {
            out += "<w:numPr><w:ilvl w:val=\"\(numbering.level)\"/><w:numId w:val=\"\(numbering.numId)\"/></w:numPr>"
        }
        out += extra
        if spacingAfter != nil || spacingBefore != nil {
            out += "<w:spacing"
            if let spacingBefore { out += " w:before=\"\(spacingBefore)\"" }
            if let spacingAfter { out += " w:after=\"\(spacingAfter)\"" }
            out += "/>"
        }
        if let indentLeft {
            out += "<w:ind w:left=\"\(indentLeft)\""
            if let hanging { out += " w:hanging=\"\(hanging)\"" }
            out += "/>"
        }
        if let alignment { out += "<w:jc w:val=\"\(alignment)\"/>" }
        return out + "</w:pPr>"
    }
}

private final class DocxWriter {
    let options: DocxExportOptions
    private var body = ""
    /// Relationships of `document.xml`: (id, type, target, external).
    private var relationships: [(id: String, type: String, target: String, external: Bool)] = []
    private var media: [(name: String, data: Data)] = []
    private var mediaExtensions: Set<String> = []
    private var drawingCount = 0
    /// Start numbers of the ordered lists, one definition each so lists
    /// never continue each other's count (a shared definition with
    /// `startOverride` is what renderers get wrong). Ids 1–3 are fixed
    /// (bullets, task unchecked, task checked).
    private var orderedLists: [(numId: Int, level: Int, start: Int)] = []

    private static let bulletNumId = 1
    private static let uncheckedNumId = 2
    private static let checkedNumId = 3

    init(options: DocxExportOptions) {
        self.options = options
    }

    private func esc(_ text: String) -> String { MarkdownDocxExporter.escape(text) }

    // MARK: Blocks

    func render(_ document: Document) {
        var context = BlockContext()
        for child in document.children {
            block(child, &context)
        }
        if body.isEmpty { body = "<w:p/>" }
    }

    private func blocks(_ markup: Markup, _ context: inout BlockContext) {
        for child in markup.children {
            block(child, &context)
        }
    }

    private func block(_ markup: Markup, _ context: inout BlockContext) {
        switch markup {
        case let paragraph as Paragraph:
            self.paragraph(paragraph, &context)
        case let heading as Heading:
            var props = ParagraphProperties(style: "Heading\(min(heading.level, 6))")
            if context.indent > 0 { props.indentLeft = context.indent }
            props.alignment = context.alignment
            emit(props, runs: inlines(heading, RunStyle()))
        case let code as CodeBlock:
            codeBlock(code, &context)
        case let quote as BlockQuote:
            var inner = context
            inner.quoteDepth += 1
            inner.pendingNumber = nil
            blocks(quote, &inner)
        case is ThematicBreak:
            var props = ParagraphProperties()
            props.extra = "<w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"D2D2D7\"/></w:pBdr>"
            props.spacingBefore = 240
            props.spacingAfter = 240
            if context.indent > 0 { props.indentLeft = context.indent }
            emit(props, runs: "")
        case let list as UnorderedList:
            self.list(list, numId: Self.bulletNumId, &context)
        case let list as OrderedList:
            let level = context.listLevel + 1
            let numId = 4 + orderedLists.count
            orderedLists.append((numId, level, Int(list.startIndex)))
            self.list(list, numId: numId, &context)
        case let table as Table:
            self.table(table, &context)
        case let html as HTMLBlock:
            let lines = html.rawHTML.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
            var style = RunStyle()
            style.html = true
            codeLines(lines, style: style, &context)
        default:
            blocks(markup, &context)
        }
    }

    private func paragraph(_ paragraph: Paragraph, _ context: inout BlockContext) {
        emit(paragraphProperties(&context), runs: inlines(paragraph, RunStyle()))
    }

    /// Properties for a plain paragraph in `context`: the first one of a
    /// list item takes the number, the rest line up under the text.
    private func paragraphProperties(_ context: inout BlockContext) -> ParagraphProperties {
        var props = ParagraphProperties()
        props.alignment = context.alignment
        if let number = context.pendingNumber {
            context.pendingNumber = nil
            props.style = "ListParagraph"
            props.numbering = number
            if context.quoteDepth > 0 {
                props.indentLeft = 720 * (number.level + 1) + 360 * context.quoteDepth
                props.hanging = 360
            }
        } else if context.inList {
            props.style = "ListParagraph"
            props.indentLeft = context.indent
        } else if context.quoteDepth > 0 {
            props.style = "Quote"
            if context.quoteDepth > 1 { props.indentLeft = context.indent }
        }
        return props
    }

    private func emit(_ props: ParagraphProperties, runs: String) {
        body += "<w:p>\(props.xml)\(runs)</w:p>"
    }

    private func codeBlock(_ code: CodeBlock, _ context: inout BlockContext) {
        var text = code.code
        if text.hasSuffix("\n") { text.removeLast() }
        // The paragraph style carries the font; the runs stay plain.
        codeLines(text.components(separatedBy: "\n"), style: RunStyle(), &context)
    }

    /// One paragraph per line in the Code style; the last line takes the
    /// body spacing back so the block does not stick to what follows.
    private func codeLines(_ lines: [String], style: RunStyle, _ context: inout BlockContext) {
        if context.pendingNumber != nil {
            // A list item that opens with code still needs its number.
            emit(paragraphProperties(&context), runs: "")
        }
        for (index, line) in lines.enumerated() {
            var props = ParagraphProperties(style: "MarcusCode")
            if context.indent > 0 { props.indentLeft = context.indent }
            if index == lines.count - 1 { props.spacingAfter = 160 }
            emit(props, runs: run(line, style))
        }
    }

    private func list(_ list: ListItemContainer, numId: Int, _ context: inout BlockContext) {
        let level = min(context.listLevel + 1, 8)
        for case let item as ListItem in list.children {
            var inner = context
            inner.listLevel = level
            let itemNumId = switch item.checkbox {
            case .checked: Self.checkedNumId
            case .unchecked: Self.uncheckedNumId
            case nil: numId
            }
            inner.pendingNumber = (itemNumId, level)
            if !(item.child(at: 0) is Paragraph) {
                // Number on its own line when the item opens with a nested
                // list, a table or a quote.
                emit(paragraphProperties(&inner), runs: "")
            }
            blocks(item, &inner)
        }
    }

    private func table(_ table: Table, _ context: inout BlockContext) {
        let alignments = table.columnAlignments
        let columns = max(table.head.cells.count { _ in true }, 1)
        func alignment(_ column: Int) -> String? {
            guard column < alignments.count, let value = alignments[column] else { return nil }
            return switch value {
            case .left: "left"
            case .center: "center"
            case .right: "right"
            }
        }
        if context.pendingNumber != nil {
            emit(paragraphProperties(&context), runs: "")
        }
        let columnWidth = Page.textWidth / columns
        // Borders and the header shading go in the style *and* directly on
        // the table: Quick Look and Pages read only the latter.
        var out = "<w:tbl><w:tblPr><w:tblStyle w:val=\"MarcusTable\"/>"
            + "<w:tblW w:w=\"0\" w:type=\"auto\"/>"
        if context.indent > 0 { out += "<w:tblInd w:w=\"\(context.indent)\" w:type=\"dxa\"/>" }
        out += DocxStyles.tableBorders
        out += "<w:tblLook w:val=\"0420\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\""
            + " w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid>"
        for _ in 0..<columns { out += "<w:gridCol w:w=\"\(columnWidth)\"/>" }
        out += "</w:tblGrid>"

        func row(_ cells: some Sequence<Table.Cell>, header: Bool) -> String {
            var out = "<w:tr>"
            if header { out += "<w:trPr><w:tblHeader/></w:trPr>" }
            var count = 0
            for (column, cell) in cells.enumerated() {
                var style = RunStyle()
                style.bold = header
                var props = ParagraphProperties()
                props.alignment = alignment(column)
                props.spacingAfter = 0
                let shading = header ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F2F4\"/>" : ""
                out += "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/>\(shading)</w:tcPr>"
                    + "<w:p>\(props.xml)\(inlines(cell, style))</w:p></w:tc>"
                count += 1
            }
            // Ragged rows: pad to the header's width so Word keeps the grid.
            while count < columns {
                out += "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr><w:p/></w:tc>"
                count += 1
            }
            return out + "</w:tr>"
        }
        out += row(table.head.cells, header: true)
        for bodyRow in table.body.rows {
            out += row(bodyRow.cells, header: false)
        }
        body += out + "</w:tbl>"
        // Word needs a paragraph after a table (two in a row would merge,
        // and the body may not end on one); kept as small as it gets.
        body += "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"120\" w:lineRule=\"exact\"/>"
            + "<w:rPr><w:sz w:val=\"2\"/></w:rPr></w:pPr></w:p>"
    }

    // MARK: Inlines

    private func inlines(_ markup: Markup, _ style: RunStyle) -> String {
        var out = ""
        for child in markup.children {
            out += inline(child, style)
        }
        return out
    }

    private func inline(_ markup: Markup, _ style: RunStyle) -> String {
        switch markup {
        case let text as Text:
            return run(text.string, style)
        case is SoftBreak:
            return run(" ", style)
        case is LineBreak:
            return "<w:r><w:br/></w:r>"
        case let emphasis as Emphasis:
            var inner = style
            inner.italic = true
            return inlines(emphasis, inner)
        case let strong as Strong:
            var inner = style
            inner.bold = true
            return inlines(strong, inner)
        case let strikethrough as Strikethrough:
            var inner = style
            inner.strike = true
            return inlines(strikethrough, inner)
        case let code as InlineCode:
            var inner = style
            inner.code = true
            return run(code.code, inner)
        case let link as Link:
            return hyperlink(link, style)
        case let image as Image:
            return self.image(image, style)
        case let html as InlineHTML:
            var inner = style
            inner.html = true
            return run(html.rawHTML, inner)
        default:
            return inlines(markup, style)
        }
    }

    private func run(_ text: String, _ style: RunStyle) -> String {
        guard !text.isEmpty else { return "" }
        var rPr = ""
        if style.link { rPr += "<w:rStyle w:val=\"Hyperlink\"/>" }
        else if style.code { rPr += "<w:rStyle w:val=\"MarcusInlineCode\"/>" }
        if style.html { rPr += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\" w:cs=\"Menlo\"/>" }
        if style.bold { rPr += "<w:b/><w:bCs/>" }
        if style.italic { rPr += "<w:i/><w:iCs/>" }
        if style.strike { rPr += "<w:strike/>" }
        if style.html { rPr += "<w:color w:val=\"6E6E73\"/><w:sz w:val=\"20\"/>" }
        var out = "<w:r>"
        if !rPr.isEmpty { out += "<w:rPr>\(rPr)</w:rPr>" }
        let pieces = text.components(separatedBy: "\t")
        for (index, piece) in pieces.enumerated() {
            if index > 0 { out += "<w:tab/>" }
            if !piece.isEmpty { out += "<w:t xml:space=\"preserve\">\(esc(piece))</w:t>" }
        }
        return out + "</w:r>"
    }

    /// Web and mail links become Word hyperlinks (external relationships).
    /// Links to local files are written as text with the path after them —
    /// Word on another Mac would open a broken path — and `#anchors` as
    /// plain text.
    private func hyperlink(_ link: Link, _ style: RunStyle) -> String {
        guard let destination = link.destination, !destination.isEmpty else { return inlines(link, style) }
        if destination.hasPrefix("#") { return inlines(link, style) }
        if let url = LinkDestination.url(destination, relativeTo: options.baseURL), url.isFileURL || url.scheme == nil {
            return inlines(link, style) + run(" (\(destination))", style)
        }
        guard let target = externalTarget(destination) else { return inlines(link, style) }
        let id = addRelationship(
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
            target: target, external: true)
        var inner = style
        inner.link = true
        return "<w:hyperlink r:id=\"\(id)\" w:history=\"1\">\(inlines(link, inner))</w:hyperlink>"
    }

    /// A relationship target must be a well-formed URI or Word refuses the
    /// file; spaces and non-ASCII get percent-encoded, a `%` is left alone.
    private func externalTarget(_ destination: String) -> String? {
        // Modern Foundation encodes what it can on the way in; the
        // normalized form is what `absoluteString` hands back.
        if let url = URL(string: destination) { return url.absoluteString }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#%")
        guard let encoded = destination.addingPercentEncoding(withAllowedCharacters: allowed),
              URL(string: encoded) != nil else { return nil }
        return encoded
    }

    private func addRelationship(type: String, target: String, external: Bool) -> String {
        if external, let existing = relationships.first(where: { $0.target == target && $0.external }) {
            return existing.id
        }
        let id = "rId\(relationships.count + 10)"
        relationships.append((id, type, target, external))
        return id
    }

    // MARK: Images

    /// Local images go into `word/media` as DrawingML inline pictures,
    /// scaled down to the text width when wider. Formats Word does not
    /// paint reliably (SVG, WebP, HEIC…) are re-encoded as PNG. Missing or
    /// remote images become their alternative text, like the RTF.
    private func image(_ image: Image, _ style: RunStyle) -> String {
        let alt = image.plainText
        let fallback = run("[\(alt.isEmpty ? (image.source ?? "") : alt)]", style)
        guard let source = image.source,
              let url = LinkDestination.url(source, relativeTo: options.baseURL),
              url.isFileURL,
              let raw = try? Data(contentsOf: url),
              let picture = EmbeddedPicture(data: raw)
        else { return fallback }

        let index = media.count + 1
        let name = "image\(index).\(picture.pathExtension)"
        media.append((name, picture.data))
        mediaExtensions.insert(picture.pathExtension)
        let id = addRelationship(
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
            target: "media/\(name)", external: false)

        var size = picture.pointSize
        let maxWidth = Page.textWidthPoints
        if size.width > maxWidth {
            size.height *= maxWidth / size.width
            size.width = maxWidth
        }
        let cx = Int(size.width * Page.emuPerPoint)
        let cy = Int(size.height * Page.emuPerPoint)
        drawingCount += 1
        let n = drawingCount
        let descr = esc(alt)
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:effectExtent l="0" t="0" r="0" b="0"/>\
        <wp:docPr id="\(n)" name="Picture \(n)" descr="\(descr)"/>\
        <wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>\
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">\
        <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:nvPicPr><pic:cNvPr id="\(n)" name="\(esc(name))" descr="\(descr)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
        </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    // MARK: Package

    func package(title: String) -> DocxPackage {
        var parts: [(path: String, data: Data)] = []
        func add(_ path: String, _ xml: String) { parts.append((path, Data(xml.utf8))) }

        add("[Content_Types].xml", contentTypes())
        add("_rels/.rels", packageRelationships)
        add("word/document.xml", documentXML())
        add("word/_rels/document.xml.rels", documentRelationships())
        add("word/styles.xml", DocxStyles.styles)
        add("word/numbering.xml", numberingXML())
        add("word/settings.xml", DocxStyles.settings)
        add("docProps/core.xml", coreProperties(title: title))
        add("docProps/app.xml", DocxStyles.appProperties)
        for item in media {
            parts.append(("word/media/\(item.name)", item.data))
        }
        return DocxPackage(parts: parts)
    }

    private func contentTypes() -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>
        """
        for ext in mediaExtensions.sorted() {
            out += "<Default Extension=\"\(ext)\" ContentType=\"\(EmbeddedPicture.contentType(for: ext))\"/>"
        }
        out += """
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
        <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>\
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>\
        </Types>
        """
        return out
    }

    private let packageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>\
    </Relationships>
    """

    private func documentRelationships() -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>\
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
        """
        for rel in relationships {
            out += "<Relationship Id=\"\(rel.id)\" Type=\"\(rel.type)\" Target=\"\(esc(rel.target))\""
            if rel.external { out += " TargetMode=\"External\"" }
            out += "/>"
        }
        return out + "</Relationships>"
    }

    private func documentXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <w:body>\(body)\
        <w:sectPr><w:pgSz w:w="\(Page.width)" w:h="\(Page.height)"/>\
        <w:pgMar w:top="\(Page.margin)" w:right="\(Page.margin)" w:bottom="\(Page.margin)" w:left="\(Page.margin)" \
        w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>\
        </w:body></w:document>
        """
    }

    private func numberingXML() -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        """
        out += DocxStyles.abstractNumbering
        // Fixed instances: bullets (1), task unchecked (2), task checked (3).
        out += "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>"
        out += "<w:num w:numId=\"2\"><w:abstractNumId w:val=\"2\"/></w:num>"
        out += "<w:num w:numId=\"3\"><w:abstractNumId w:val=\"3\"/></w:num>"
        for list in orderedLists {
            out += DocxStyles.orderedAbstractNumbering(id: list.numId, level: list.level, start: list.start)
            out += "<w:num w:numId=\"\(list.numId)\"><w:abstractNumId w:val=\"\(list.numId)\"/></w:num>"
        }
        return out + "</w:numbering>"
    }

    private func coreProperties(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(esc(title))</dc:title></cp:coreProperties>
        """
    }
}

// MARK: - Pictures

/// Bytes and size of a picture as Word will store it.
private struct EmbeddedPicture {
    var data: Data
    var pathExtension: String
    var pointSize: CGSize

    /// Formats Word for Mac paints as they come; anything else is
    /// re-encoded as PNG.
    private static let passthrough: [String: String] = [
        "public.png": "png", "public.jpeg": "jpeg", "com.compuserve.gif": "gif",
        "com.microsoft.bmp": "bmp", "public.tiff": "tiff",
    ]

    static func contentType(for pathExtension: String) -> String {
        switch pathExtension {
        case "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "bmp": "image/bmp"
        case "tiff": "image/tiff"
        default: "image/png"
        }
    }

    init?(data raw: Data) {
        if let source = CGImageSourceCreateWithData(raw as CFData, nil),
           let type = CGImageSourceGetType(source) as String?,
           let ext = Self.passthrough[type],
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            // Pixels to points through the file's own resolution: a 144 dpi
            // Retina screenshot comes out at half its pixel size, as on
            // screen.
            let dpi = (properties[kCGImagePropertyDPIWidth] as? CGFloat).flatMap { $0 > 0 ? $0 : nil } ?? 72
            data = raw
            pathExtension = ext
            pointSize = CGSize(width: width * 72 / dpi, height: height * 72 / dpi)
            return
        }
        // SVG, WebP, HEIC…: let AppKit decode and rasterize at 2× for
        // Retina-grade output in the document.
        guard let image = NSImage(data: raw), image.size.width > 0, image.size.height > 0 else { return nil }
        let size = image.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        data = png
        pathExtension = "png"
        pointSize = size
    }
}

// MARK: - Fixed parts

private enum DocxStyles {

    /// Built-in style ids and *names* (`heading 1`, `Quote`, `List
    /// Paragraph`, `Hyperlink`) are Word's own, so Word localizes them
    /// (Título 1…) and the navigation pane, TOC and gallery pick them up.
    /// The two of ours carry a prefix and English names. Paper palette:
    /// the HTML export's light inks (`PreviewPalette.paper`).
    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:docDefaults>\
    <w:rPrDefault><w:rPr><w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue" w:cs="Helvetica Neue" w:eastAsia="Helvetica Neue"/>\
    <w:color w:val="1D1D1F"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>\
    </w:docDefaults>\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/>\
    <w:rPr><w:rFonts w:ascii="Helvetica Neue" w:hAnsi="Helvetica Neue" w:cs="Helvetica Neue" w:eastAsia="Helvetica Neue"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:style>\
    \(headings)\
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="D2D2D7"/></w:pBdr><w:ind w:left="360"/></w:pPr>\
    <w:rPr><w:color w:val="6E6E73"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style>\
    <w:style w:type="paragraph" w:styleId="MarcusCode"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:keepLines/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F4"/><w:spacing w:after="0" w:line="264" w:lineRule="auto"/>\
    <w:ind w:left="0"/></w:pPr>\
    <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo" w:eastAsia="Menlo"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>\
    <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/></w:style>\
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:basedOn w:val="DefaultParagraphFont"/>\
    <w:rPr><w:color w:val="0066CC"/><w:u w:val="single"/></w:rPr></w:style>\
    <w:style w:type="character" w:styleId="MarcusInlineCode"><w:name w:val="Inline Code"/><w:basedOn w:val="DefaultParagraphFont"/><w:qFormat/>\
    <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Menlo" w:eastAsia="Menlo"/><w:sz w:val="20"/><w:szCs w:val="20"/>\
    <w:shd w:val="clear" w:color="auto" w:fill="F2F2F4"/></w:rPr></w:style>\
    <w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:semiHidden/>\
    <w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>\
    <w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>\
    <w:style w:type="table" w:styleId="MarcusTable"><w:name w:val="Marcus Table"/><w:basedOn w:val="TableNormal"/>\
    <w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>\
    <w:tblPr>\(tableBorders)<w:tblCellMar><w:top w:w="60" w:type="dxa"/><w:left w:w="120" w:type="dxa"/>\
    <w:bottom w:w="60" w:type="dxa"/><w:right w:w="120" w:type="dxa"/></w:tblCellMar></w:tblPr>\
    <w:tblStylePr w:type="firstRow"><w:rPr><w:b/><w:bCs/></w:rPr>\
    <w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="F2F2F4"/></w:tcPr></w:tblStylePr>\
    </w:style>\
    </w:styles>
    """

    static let tableBorders = "<w:tblBorders>"
        + "<w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D2D2D7\"/><w:left w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D2D2D7\"/>"
        + "<w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D2D2D7\"/><w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D2D2D7\"/>"
        + "<w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D2D2D7\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"D2D2D7\"/>"
        + "</w:tblBorders>"

    /// Heading 1–6 on paper: sizes in half-points, dark ink, kept with
    /// the next paragraph; `outlineLvl` is what the navigation pane and
    /// the table of contents read.
    private static let headings: String = {
        let sizes = [44, 34, 28, 24, 22, 22]
        let before = [480, 360, 280, 240, 200, 200]
        var out = ""
        for level in 1...6 {
            out += "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(level)\"><w:name w:val=\"heading \(level)\"/>"
                + "<w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/>"
                + "<w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"\(before[level - 1])\" w:after=\"120\" w:line=\"252\" w:lineRule=\"auto\"/>"
                + "<w:outlineLvl w:val=\"\(level - 1)\"/></w:pPr>"
                + "<w:rPr><w:b/><w:bCs/>\(level == 6 ? "<w:i/><w:iCs/>" : "")"
                + "<w:sz w:val=\"\(sizes[level - 1])\"/><w:szCs w:val=\"\(sizes[level - 1])\"/></w:rPr></w:style>"
        }
        return out
    }()

    /// Three fixed definitions, nine levels each: bullets (• ◦ ▪), task
    /// unchecked (☐) and task checked (☑). The checkbox glyphs ride as the
    /// "bullet" so tasks indent and nest like any list; Menlo has both
    /// glyphs on every Mac. Ordered lists get their own definition each
    /// (`orderedAbstractNumbering`).
    static let abstractNumbering: String = {
        let bullets = ["•", "◦", "▪"]
        return "<w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"hybridMultilevel\"/>"
            + levels({ bullets[$0 % 3] }, format: { _ in "bullet" }, font: nil) + "</w:abstractNum>"
            + "<w:abstractNum w:abstractNumId=\"2\"><w:multiLevelType w:val=\"hybridMultilevel\"/>"
            + levels({ _ in "☐" }, format: { _ in "bullet" }, font: "Menlo") + "</w:abstractNum>"
            + "<w:abstractNum w:abstractNumId=\"3\"><w:multiLevelType w:val=\"hybridMultilevel\"/>"
            + levels({ _ in "☑" }, format: { _ in "bullet" }, font: "Menlo") + "</w:abstractNum>"
    }()

    /// Decimal at every level, as the preview and the HTML show them; the
    /// list's own start number sits at its level.
    static func orderedAbstractNumbering(id: Int, level: Int, start: Int) -> String {
        "<w:abstractNum w:abstractNumId=\"\(id)\"><w:multiLevelType w:val=\"hybridMultilevel\"/>"
            + levels({ "%\($0 + 1)." }, format: { _ in "decimal" }, font: nil, start: { $0 == level ? start : 1 })
            + "</w:abstractNum>"
    }

    private static func levels(_ text: (Int) -> String, format: (Int) -> String, font: String?,
                               start: (Int) -> Int = { _ in 1 }) -> String {
            var out = ""
            for level in 0..<9 {
                out += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"\(start(level))\"/><w:numFmt w:val=\"\(format(level))\"/>"
                    + "<w:lvlText w:val=\"\(text(level))\"/><w:lvlJc w:val=\"left\"/>"
                    + "<w:pPr><w:ind w:left=\"\(720 * (level + 1))\" w:hanging=\"360\"/></w:pPr>"
                if let font {
                    out += "<w:rPr><w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:cs=\"\(font)\" w:hint=\"default\"/></w:rPr>"
                }
                out += "</w:lvl>"
            }
            return out
    }

    /// Without a compatibility mode Word opens the file in "Compatibility
    /// Mode" and nags; 15 is Word 2013 and later.
    static let settings = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/>\
    <w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>\
    </w:settings>
    """

    static let appProperties = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" \
    xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">\
    <Application>Marcus</Application></Properties>
    """
}
