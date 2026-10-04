import XCTest
import AppKit
@testable import MarcusPreview

/// Round trips for the Word export: the package's XML is inspected part by
/// part, the zip is checked by the system's own `unzip`, every XML part
/// must parse, and AppKit's OOXML reader must open the file and find the
/// text — what Word, Pages or Quick Look would get. AppKit's reader ignores
/// styles, numbering, links and pictures, so those are asserted in the XML.
final class MarkdownDocxExporterTests: XCTestCase {

    private func package(_ markdown: String, title: String = "Untitled", baseURL: URL? = nil) -> DocxPackage {
        MarkdownDocxExporter.package(from: markdown, options: DocxExportOptions(title: title, baseURL: baseURL))
    }

    private func document(_ markdown: String, baseURL: URL? = nil) throws -> String {
        try XCTUnwrap(package(markdown, baseURL: baseURL).xml("word/document.xml"))
    }

    private func temporaryFolder() throws -> URL {
        // A directory URL (trailing slash): relative paths resolve inside it.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func writePNG(to url: URL, width: Int = 40, height: Int = 20) throws {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let png = NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:])
        try XCTUnwrap(png).write(to: url)
    }

    // MARK: Package

    func testPackageHasTheRequiredParts() {
        let paths = package("Hola").parts.map(\.path)
        for required in ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/_rels/document.xml.rels",
                         "word/styles.xml", "word/numbering.xml", "word/settings.xml", "docProps/core.xml"] {
            XCTAssertTrue(paths.contains(required), required)
        }
        XCTAssertEqual(paths.first, "[Content_Types].xml")
    }

    /// Every XML part must parse: one stray `&` or control character and
    /// Word refuses the whole file.
    func testEveryXMLPartParses() throws {
        let markdown = "# T & <x>\n\n\"quotes\" `a < b` [l](https://e.com/?a=1&b=2)\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [ ] t\n\n```\nx\u{0}y\n```"
        for part in package(markdown).parts where part.path.hasSuffix(".xml") || part.path.hasSuffix(".rels") {
            XCTAssertNoThrow(try XMLDocument(data: part.data, options: []), part.path)
        }
    }

    /// The zip is checked by the system's own tool: headers, CRCs, sizes.
    func testZipPassesUnzipIntegrityCheck() throws {
        let url = try temporaryFolder().appendingPathComponent("doc.docx")
        try MarkdownDocxExporter.data(from: "# Hola\n\nMundo **fuerte**").write(to: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testCRC32MatchesTheReferenceValue() {
        XCTAssertEqual(ZipArchiveWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(ZipArchiveWriter.crc32(Data()), 0)
    }

    /// AppKit's reader opens the file: the text and the title survive the
    /// trip through a reader we did not write.
    func testAppKitReaderOpensTheDocument() throws {
        let url = try temporaryFolder().appendingPathComponent("doc.docx")
        let markdown = "---\ntitle: Notas de prueba\n---\n# Título\n\nPárrafo con **negrita** y `código`.\n\n- uno\n- dos\n\n| a | b |\n|---|---|\n| 1 | 2 |"
        try MarkdownDocxExporter.data(from: markdown).write(to: url)
        var info: NSDictionary?
        let string = try NSAttributedString(
            url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: &info)
        XCTAssertTrue(string.string.contains("Título"))
        XCTAssertTrue(string.string.contains("Párrafo con negrita y código."))
        XCTAssertTrue(string.string.contains("uno"))
        XCTAssertFalse(string.string.contains("title:"))
        XCTAssertEqual(info?[NSAttributedString.DocumentAttributeKey.title] as? String, "Notas de prueba")
    }

    // MARK: Blocks

    func testHeadingsUseWordsBuiltInStyles() throws {
        let xml = try document("# Uno\n\n## Dos\n\n###### Seis\n\n####### Siete")
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Heading1\"/>"))
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Heading2\"/>"))
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Heading6\"/>"))
        let styles = try XCTUnwrap(package("").xml("word/styles.xml"))
        // The built-in *name* is what Word localizes (Título 1) and what the
        // navigation pane and the table of contents read, with outlineLvl.
        XCTAssertTrue(styles.contains("<w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/>"))
        XCTAssertTrue(styles.contains("<w:outlineLvl w:val=\"0\"/>"))
        XCTAssertTrue(styles.contains("<w:outlineLvl w:val=\"5\"/>"))
    }

    func testEmphasisBecomesRunProperties() throws {
        let xml = try document("plain **bold** *italic* ~~gone~~ `code`")
        XCTAssertTrue(xml.contains("<w:rPr><w:b/><w:bCs/></w:rPr><w:t xml:space=\"preserve\">bold</w:t>"))
        XCTAssertTrue(xml.contains("<w:rPr><w:i/><w:iCs/></w:rPr><w:t xml:space=\"preserve\">italic</w:t>"))
        XCTAssertTrue(xml.contains("<w:rPr><w:strike/></w:rPr><w:t xml:space=\"preserve\">gone</w:t>"))
        XCTAssertTrue(xml.contains("<w:rStyle w:val=\"MarcusInlineCode\"/></w:rPr><w:t xml:space=\"preserve\">code</w:t>"))
    }

    func testCodeBlockIsOneCodeParagraphPerLineWithTabs() throws {
        let xml = try document("```swift\nlet x = 1\n\tindented\n\nlast\n```\n\nAfter")
        let lines = xml.components(separatedBy: "<w:pStyle w:val=\"MarcusCode\"/>").count - 1
        XCTAssertEqual(lines, 4)
        XCTAssertTrue(xml.contains("<w:tab/><w:t xml:space=\"preserve\">indented</w:t>"))
        // The last line restores the body spacing so the block breathes.
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"MarcusCode\"/><w:spacing w:after=\"160\"/></w:pPr><w:r><w:t xml:space=\"preserve\">last</w:t>"))
        XCTAssertFalse(xml.contains("swift"), "the language is not content")
    }

    func testQuotesUseTheQuoteStyle() throws {
        let xml = try document("> Cita\n>\n> > Anidada")
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Quote\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Cita</w:t>"))
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Quote\"/><w:ind w:left=\"720\"/></w:pPr><w:r><w:t xml:space=\"preserve\">Anidada</w:t>"))
    }

    func testThematicBreakIsABottomBorder() throws {
        let xml = try document("a\n\n---\n\nb")
        XCTAssertTrue(xml.contains("<w:pBdr><w:bottom w:val=\"single\""))
    }

    func testRawHTMLStaysAsGrayMonospacedText() throws {
        let xml = try document("<div>block</div>\n\nText <b>inline</b>")
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">&lt;div&gt;block&lt;/div&gt;</w:t>"))
        XCTAssertTrue(xml.contains("<w:color w:val=\"6E6E73\"/><w:sz w:val=\"20\"/></w:rPr><w:t xml:space=\"preserve\">&lt;b&gt;</w:t>"))
    }

    func testSoftAndHardBreaks() throws {
        let xml = try document("one\ntwo  \nthree")
        XCTAssertTrue(xml.contains(">one</w:t></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r><w:r><w:t xml:space=\"preserve\">two</w:t>"))
        XCTAssertTrue(xml.contains("<w:r><w:br/></w:r>"))
    }

    // MARK: Lists

    func testBulletsAndNestingUseWordNumbering() throws {
        let xml = try document("- uno\n- dos\n  - anidado")
        XCTAssertTrue(xml.contains("<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">uno</w:t>"))
        XCTAssertTrue(xml.contains("<w:numPr><w:ilvl w:val=\"1\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">anidado</w:t>"))
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"ListParagraph\"/>"))
    }

    /// Each ordered list owns its definition with its start number: two
    /// lists in a row never continue each other, and `3.` starts at 3.
    func testOrderedListsRestartAndKeepTheirStart() throws {
        let pkg = package("1. a\n2. b\n\ntext\n\n3. c\n4. d")
        let xml = try XCTUnwrap(pkg.xml("word/document.xml"))
        let numbering = try XCTUnwrap(pkg.xml("word/numbering.xml"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"4\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">a</w:t>"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"5\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">c</w:t>"))
        XCTAssertTrue(numbering.contains("<w:abstractNum w:abstractNumId=\"5\"><w:multiLevelType w:val=\"hybridMultilevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"3\"/><w:numFmt w:val=\"decimal\"/>"))
        XCTAssertTrue(numbering.contains("<w:num w:numId=\"5\"><w:abstractNumId w:val=\"5\"/></w:num>"))
    }

    /// Tasks ride on two fixed definitions whose "bullet" is the box glyph.
    func testTasksUseCheckboxGlyphNumbering() throws {
        let pkg = package("- [ ] pendiente\n- [x] hecha\n- normal")
        let xml = try XCTUnwrap(pkg.xml("word/document.xml"))
        let numbering = try XCTUnwrap(pkg.xml("word/numbering.xml"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"2\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">pendiente</w:t>"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"3\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">hecha</w:t>"))
        XCTAssertTrue(xml.contains("<w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">normal</w:t>"))
        XCTAssertTrue(numbering.contains("<w:lvlText w:val=\"☐\"/>"))
        XCTAssertTrue(numbering.contains("<w:lvlText w:val=\"☑\"/>"))
    }

    func testListItemWithSeveralBlocksNumbersOnlyTheFirst() throws {
        let xml = try document("- primero\n\n  segundo\n\n  ```\n  code\n  ```")
        XCTAssertEqual(xml.components(separatedBy: "<w:numPr>").count - 1, 1)
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"ListParagraph\"/><w:ind w:left=\"720\"/></w:pPr><w:r><w:t xml:space=\"preserve\">segundo</w:t>"))
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"MarcusCode\"/><w:spacing w:after=\"160\"/><w:ind w:left=\"720\"/></w:pPr>"))
    }

    // MARK: Tables

    func testTableHasRepeatingHeaderAlignmentAndPaddedRows() throws {
        let xml = try document("| A | B | C |\n|:--|:-:|--:|\n| a | b | c |\n| 1 | 2 |")
        XCTAssertTrue(xml.contains("<w:tblStyle w:val=\"MarcusTable\"/>"))
        XCTAssertTrue(xml.contains("<w:tblHeader/>"))
        XCTAssertTrue(xml.contains("<w:jc w:val=\"center\"/></w:pPr><w:r><w:rPr><w:b/><w:bCs/></w:rPr><w:t xml:space=\"preserve\">B</w:t>"))
        XCTAssertTrue(xml.contains("<w:jc w:val=\"right\"/></w:pPr><w:r><w:t xml:space=\"preserve\">c</w:t>"))
        XCTAssertEqual(xml.components(separatedBy: "<w:gridCol").count - 1, 3)
        XCTAssertEqual(xml.components(separatedBy: "<w:tc>").count - 1, 9, "the short row is padded to three cells")
        // A paragraph after the table, so the body never ends on one.
        XCTAssertTrue(xml.contains("</w:tbl><w:p>"))
    }

    // MARK: Links

    func testWebLinksBecomeHyperlinksWithExternalRelationships() throws {
        let pkg = package("see [the site](https://example.com/p?a=1&b=2) and [mail](mailto:a@b.c)")
        let xml = try XCTUnwrap(pkg.xml("word/document.xml"))
        let rels = try XCTUnwrap(pkg.xml("word/_rels/document.xml.rels"))
        XCTAssertTrue(xml.contains("<w:hyperlink r:id=\"rId10\" w:history=\"1\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/></w:rPr><w:t xml:space=\"preserve\">the site</w:t>"))
        XCTAssertTrue(rels.contains("Id=\"rId10\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"https://example.com/p?a=1&amp;b=2\" TargetMode=\"External\""))
        XCTAssertTrue(rels.contains("Target=\"mailto:a@b.c\" TargetMode=\"External\""))
    }

    /// CommonMark only admits spaces in a destination between `<…>`; the
    /// relationship target must still be a well-formed URI.
    func testLinksWithSpacesArePercentEncodedForTheRelationship() throws {
        let rels = try XCTUnwrap(package("[x](<https://example.com/a b/ñ>)").xml("word/_rels/document.xml.rels"))
        XCTAssertTrue(rels.contains("Target=\"https://example.com/a%20b/%C3%B1\" TargetMode=\"External\""), rels)
    }

    /// Local files would open a broken path on another Mac; anchors have
    /// no target in Word. Both stay as text.
    func testLocalAndAnchorLinksStayAsText() throws {
        let pkg = package("[otro](otro.md) y [arriba](#top) y [abs](file:///tmp/x.md)")
        let xml = try XCTUnwrap(pkg.xml("word/document.xml"))
        XCTAssertFalse(xml.contains("<w:hyperlink"))
        XCTAssertTrue(xml.contains(">otro</w:t></w:r><w:r><w:t xml:space=\"preserve\"> (otro.md)</w:t>"))
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">arriba</w:t></w:r><w:r><w:t xml:space=\"preserve\"> y </w:t>"))
        XCTAssertTrue(xml.contains("> (file:///tmp/x.md)</w:t>"))
    }

    // MARK: Images

    func testLocalImagesAreEmbeddedWithTheirSizeAndAltText() throws {
        let folder = try temporaryFolder()
        try writePNG(to: folder.appendingPathComponent("dot.png"), width: 40, height: 20)
        let pkg = package("![Un punto](dot.png)", baseURL: folder)
        let xml = try XCTUnwrap(pkg.xml("word/document.xml"))
        let rels = try XCTUnwrap(pkg.xml("word/_rels/document.xml.rels"))
        let types = try XCTUnwrap(pkg.xml("[Content_Types].xml"))
        XCTAssertNotNil(pkg.part("word/media/image1.png"))
        XCTAssertTrue(xml.contains("<w:drawing><wp:inline"))
        // 40 × 20 points at 72 dpi → EMUs (12700 per point).
        XCTAssertTrue(xml.contains("<wp:extent cx=\"508000\" cy=\"254000\"/>"))
        XCTAssertTrue(xml.contains("descr=\"Un punto\""))
        XCTAssertTrue(xml.contains("<a:blip r:embed=\"rId10\"/>"))
        XCTAssertTrue(rels.contains("Id=\"rId10\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image1.png\"/>"))
        XCTAssertTrue(types.contains("<Default Extension=\"png\" ContentType=\"image/png\"/>"))
    }

    func testWideImagesAreScaledToTheTextWidth() throws {
        let folder = try temporaryFolder()
        try writePNG(to: folder.appendingPathComponent("wide.png"), width: 2000, height: 1000)
        let xml = try document("![w](wide.png)", baseURL: folder)
        // Text width is 468 pt (Letter) or 451.3 pt (A4); either way < 500.
        let extent = try XCTUnwrap(xml.range(of: "<wp:extent cx=\"([0-9]+)\" cy=\"([0-9]+)\"/>", options: .regularExpression))
        let numbers = xml[extent].components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 2)
        XCTAssertLessThan(numbers[0], 500 * 12700)
        XCTAssertGreaterThan(numbers[0], 400 * 12700)
        XCTAssertEqual(numbers[1] * 2, numbers[0], accuracy: 12700, "aspect ratio kept")
    }

    /// Formats Word does not paint reliably are re-encoded as PNG.
    func testSVGIsConvertedToPNG() throws {
        let folder = try temporaryFolder()
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"30\" height=\"10\"><rect width=\"30\" height=\"10\" fill=\"blue\"/></svg>"
        try svg.write(to: folder.appendingPathComponent("v.svg"), atomically: true, encoding: .utf8)
        let pkg = package("![v](v.svg)", baseURL: folder)
        let png = try XCTUnwrap(pkg.part("word/media/image1.png"))
        XCTAssertEqual([UInt8](png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertTrue(try XCTUnwrap(pkg.xml("word/document.xml")).contains("<wp:extent cx=\"381000\" cy=\"127000\"/>"))
    }

    func testMissingAndRemoteImagesBecomeAlternativeText() throws {
        let xml = try document("![falta](nope.png) ![](https://example.com/x.png)")
        XCTAssertFalse(xml.contains("<w:drawing>"))
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">[falta]</w:t>"))
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">[https://example.com/x.png]</w:t>"))
        XCTAssertTrue(package("![falta](nope.png)").parts.allSatisfy { !$0.path.hasPrefix("word/media/") })
    }

    // MARK: Front matter and title

    func testFrontMatterIsOmittedAndItsTitleGoesToTheProperties() throws {
        let pkg = package("---\ntitle: \"Mi informe\"\nauthor: yo\n---\n# Doc", title: "archivo")
        XCTAssertFalse(try XCTUnwrap(pkg.xml("word/document.xml")).contains("author"))
        XCTAssertTrue(try XCTUnwrap(pkg.xml("docProps/core.xml")).contains("<dc:title>Mi informe</dc:title>"))
    }

    func testFileNameIsTheTitleWithoutFrontMatter() throws {
        let core = try XCTUnwrap(package("# Doc", title: "Notas & cosas").xml("docProps/core.xml"))
        XCTAssertTrue(core.contains("<dc:title>Notas &amp; cosas</dc:title>"))
    }

    // MARK: Robustness

    func testControlCharactersAreDroppedAndMarkupEscaped() throws {
        let xml = try document("a\u{1}b & c")
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">ab &amp; c</w:t>"), xml)
        XCTAssertFalse(xml.contains("\u{1}"))
        XCTAssertEqual(MarkdownDocxExporter.escape("<\"&\u{B}>"), "&lt;&quot;&amp;&gt;")
    }

    func testEmptyDocumentStillHasAParagraph() throws {
        let xml = try document("")
        XCTAssertTrue(xml.contains("<w:body><w:p/>"))
    }

    func testSameInputGivesSameBytes() {
        XCTAssertEqual(MarkdownDocxExporter.data(from: "# A\n\nb"), MarkdownDocxExporter.data(from: "# A\n\nb"))
    }
}
