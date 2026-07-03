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

    func testMissingImageShowsPlaceholder() {
        let rendered = render("![alt](no-such-file.png)")
        XCTAssertTrue(rendered.string.contains("no-such-file.png"))
    }

    func testBlockquoteIsSecondaryColor() {
        let rendered = render("> cita")
        let color = attributes(in: rendered, at: "cita")?[.foregroundColor] as? NSColor
        XCTAssertEqual(color, .secondaryLabelColor)
    }

    func testEmptyDocumentRendersEmpty() {
        XCTAssertEqual(render("").string, "")
    }
}
