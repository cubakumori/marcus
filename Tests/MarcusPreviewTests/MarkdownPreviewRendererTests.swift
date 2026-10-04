import XCTest
import AppKit
@testable import MarcusPreview

final class MarkdownPreviewRendererTests: XCTestCase {

    private func render(_ markdown: String) -> NSAttributedString {
        MarkdownPreviewRenderer.render(markdown).string
    }

    private func attributes(in rendered: NSAttributedString, at substring: String) -> [NSAttributedString.Key: Any]? {
        let range = (rendered.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return rendered.attributes(at: range.location, effectiveRange: nil)
    }

    func testHeadingIsLargerAndHeavierThanBody() {
        let rendered = render("# Title\n\nBody text.")
        let headingFont = attributes(in: rendered, at: "Title")?[.font] as? NSFont
        let bodyFont = attributes(in: rendered, at: "Body")?[.font] as? NSFont
        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        XCTAssertGreaterThan(headingFont!.pointSize, bodyFont!.pointSize)
    }

    func testStrongIsBold() {
        let rendered = render("plain **bold** plain")
        let font = attributes(in: rendered, at: "bold")?[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(NSFontManager.shared.traits(of: font!).contains(.boldFontMask))
    }

    func testEmphasisIsItalic() {
        let rendered = render("plain *italico* plain")
        let font = attributes(in: rendered, at: "italico")?[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(NSFontManager.shared.traits(of: font!).contains(.italicFontMask))
    }

    func testInlineCodeIsMonospaced() {
        let rendered = render("with `codigo` inline")
        let font = attributes(in: rendered, at: "codigo")?[.font] as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testCodeBlockKeepsContentAndMonospace() {
        let rendered = render("```swift\nlet x = 1\n```")
        XCTAssertTrue(rendered.string.contains("let x = 1"))
        let font = attributes(in: rendered, at: "let x")?[.font] as? NSFont
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    func testLinkCarriesURL() {
        let rendered = render("see [docs](https://example.com/a)")
        let url = attributes(in: rendered, at: "docs")?[.link] as? URL
        XCTAssertEqual(url?.absoluteString, "https://example.com/a")
    }

    func testRelativeLinkResolvesAgainstBaseURL() {
        let base = URL(fileURLWithPath: "/tmp/docs/")
        let rendered = MarkdownPreviewRenderer.render("[a](other.md)", options: .init(baseURL: base)).string
        let url = attributes(in: rendered, at: "a")?[.link] as? URL
        XCTAssertEqual(url?.path, "/tmp/docs/other.md")
    }

    func testUnorderedListHasBullets() {
        let rendered = render("- uno\n- dos")
        XCTAssertTrue(rendered.string.contains("•  uno"))
        XCTAssertTrue(rendered.string.contains("•  dos"))
    }

    func testOrderedListNumbersFromStart() {
        let rendered = render("3. tres\n4. cuatro")
        XCTAssertTrue(rendered.string.contains("3.  tres"))
        XCTAssertTrue(rendered.string.contains("4.  cuatro"))
    }

    func testTaskListCheckboxes() {
        let rendered = render("- [x] hecho\n- [ ] pendiente")
        XCTAssertTrue(rendered.string.contains("☑ hecho"))
        XCTAssertTrue(rendered.string.contains("☐ pendiente"))
    }

    func testStrikethrough() {
        let rendered = render("~~tachado~~")
        let style = attributes(in: rendered, at: "tachado")?[.strikethroughStyle] as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testTableRendersAllCells() {
        let rendered = render("| a | b |\n|---|---|\n| c1 | c2 |")
        XCTAssertTrue(rendered.string.contains("a"))
        XCTAssertTrue(rendered.string.contains("c1"))
        XCTAssertTrue(rendered.string.contains("c2"))
    }

    func testTableRightAlignmentPadsLeading() {
        let lines = render("| Num |\n|----:|\n| 1 |").string.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "Num")
        XCTAssertEqual(lines[1], "───")
        XCTAssertEqual(lines[2], "  1")  // right-aligned: padded on the left
    }

    func testTableCenterAlignment() {
        let lines = render("| Mid |\n|:---:|\n| x |").string.components(separatedBy: "\n")
        XCTAssertEqual(lines[2], " x ")  // centered: split padding
    }

    func testTableLeftAlignmentPadsTrailing() {
        let lines = render("| Abc |\n|:----|\n| x |").string.components(separatedBy: "\n")
        XCTAssertEqual(lines[2], "x  ")  // left-aligned: padded on the right
    }

    func testTablePreservesBoldInCell() {
        let rendered = render("| H |\n|---|\n| **b** |")
        let range = (rendered.string as NSString).range(of: "b")
        let font = rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testTablePreservesLinkInCell() {
        let rendered = render("| H |\n|---|\n| [x](https://e.com) |")
        var foundLink = false
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { foundLink = true }
        }
        XCTAssertTrue(foundLink)
    }

    func testMissingImageShowsPlaceholder() {
        let rendered = render("![alt](no-such-file.png)")
        XCTAssertTrue(rendered.string.contains("no-such-file.png"))
    }

    /// Accents plus percent escapes — what Insert Image… writes for
    /// `año/mi foto.png` — must still find the file (`URL(string:)` alone
    /// re-encoded the `%` and looked for `mi%20foto.png`).
    func testImageWithAccentsAndEscapesIsFound() throws {
        // A directory URL (trailing slash): without it, Foundation resolves
        // the relative path against the folder's *parent*. The URL is
        // built before the folder exists, so `appendingPathComponent`
        // cannot tell on its own.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = folder.appendingPathComponent("año")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:])
        try XCTUnwrap(png).write(to: sub.appendingPathComponent("mi foto.png"))

        let rendered = MarkdownPreviewRenderer.render("![x](año/mi%20foto.png)", options: .init(baseURL: folder)).string
        var attachments = 0
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertEqual(attachments, 1, rendered.string)
    }

    func testBlockquoteIsSecondaryColor() {
        let rendered = render("> cita")
        let color = attributes(in: rendered, at: "cita")?[.foregroundColor] as? NSColor
        XCTAssertEqual(color, .secondaryLabelColor)
    }

    func testEmptyDocumentRendersEmpty() {
        XCTAssertEqual(render("").string, "")
    }

    // MARK: Palette

    func testDefaultPaletteUsesSystemColors() {
        let rendered = render("plain body")
        let color = attributes(in: rendered, at: "plain")?[.foregroundColor] as? NSColor
        XCTAssertEqual(color, .labelColor)
    }

    func testCustomPaletteColorsBodyAndBlockquote() {
        let palette = PreviewPalette(text: .systemRed, secondaryText: .systemBrown)
        let rendered = MarkdownPreviewRenderer.render(
            "body text\n\n> quoted", options: .init(palette: palette)).string
        XCTAssertEqual(attributes(in: rendered, at: "body")?[.foregroundColor] as? NSColor, .systemRed)
        XCTAssertEqual(attributes(in: rendered, at: "quoted")?[.foregroundColor] as? NSColor, .systemBrown)
    }

    func testCustomPaletteColorsInlineCode() {
        let palette = PreviewPalette(code: .systemGreen, codeBackground: .systemYellow)
        let rendered = MarkdownPreviewRenderer.render(
            "with `span` here", options: .init(palette: palette)).string
        let attrs = attributes(in: rendered, at: "span")
        XCTAssertEqual(attrs?[.foregroundColor] as? NSColor, .systemGreen)
        XCTAssertEqual(attrs?[.backgroundColor] as? NSColor, .systemYellow)
    }

    func testCustomPaletteColorsLinks() {
        let palette = PreviewPalette(link: .systemOrange)
        let rendered = MarkdownPreviewRenderer.render(
            "see [docs](https://example.com)", options: .init(palette: palette)).string
        XCTAssertEqual(attributes(in: rendered, at: "docs")?[.foregroundColor] as? NSColor, .systemOrange)
    }
}
