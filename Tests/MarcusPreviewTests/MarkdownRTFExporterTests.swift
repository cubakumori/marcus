import XCTest
import AppKit
@testable import MarcusPreview

/// Round trips: export to RTF, read it back with AppKit's own reader and
/// check what survived — what Word or TextEdit would see.
final class MarkdownRTFExporterTests: XCTestCase {

    private func roundTrip(_ markdown: String, title: String? = nil, baseURL: URL? = nil)
        throws -> (string: NSAttributedString, info: [NSAttributedString.DocumentAttributeKey: Any]) {
        let data = try MarkdownRTFExporter.data(from: markdown, title: title, baseURL: baseURL)
        var info: NSDictionary?
        let string = try XCTUnwrap(NSAttributedString(rtf: data, documentAttributes: &info))
        return (string, info as? [NSAttributedString.DocumentAttributeKey: Any] ?? [:])
    }

    private func attributes(in string: NSAttributedString, at substring: String) -> [NSAttributedString.Key: Any]? {
        let range = (string.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return string.attributes(at: range.location, effectiveRange: nil)
    }

    func testOutputIsRTF() throws {
        let data = try MarkdownRTFExporter.data(from: "Hola")
        XCTAssertTrue(String(decoding: data.prefix(5), as: UTF8.self).hasPrefix("{\\rtf"))
    }

    func testTextAndEmphasisSurvive() throws {
        let (string, _) = try roundTrip("# Título\n\nplain **bold** and *italic* and ~~gone~~")
        XCTAssertTrue(string.string.contains("Título"))
        let bold = try XCTUnwrap(attributes(in: string, at: "bold")?[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let italic = try XCTUnwrap(attributes(in: string, at: "italic")?[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        XCTAssertNotNil(attributes(in: string, at: "gone")?[.strikethroughStyle])
        let heading = try XCTUnwrap(attributes(in: string, at: "Título")?[.font] as? NSFont)
        let body = try XCTUnwrap(attributes(in: string, at: "plain")?[.font] as? NSFont)
        XCTAssertGreaterThan(heading.pointSize, body.pointSize)
    }

    func testLinkSurvives() throws {
        let (string, _) = try roundTrip("see [the site](https://example.com/page)")
        let link = attributes(in: string, at: "the site")?[.link]
        let url = (link as? URL)?.absoluteString ?? link as? String
        XCTAssertEqual(url, "https://example.com/page")
    }

    func testCodeKeepsMonospaceAndBackground() throws {
        let (string, _) = try roundTrip("```\nlet x = 1\n```")
        let attrs = try XCTUnwrap(attributes(in: string, at: "let x"))
        let font = try XCTUnwrap(attrs[.font] as? NSFont)
        XCTAssertTrue(font.isFixedPitch)
        XCTAssertNotNil(attrs[.backgroundColor])
    }

    /// No private system font names (`.AppleSystemUIFont…`) in the file:
    /// Word cannot resolve them.
    func testFontsAreInstalledFamilies() throws {
        let data = try MarkdownRTFExporter.data(from: "# H\n\nBody **bold** `code`\n\n```\nblock\n```")
        let rtf = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(rtf.contains(".AppleSystemUI"), rtf)
        XCTAssertTrue(rtf.contains("Menlo"))
        let (string, _) = try roundTrip("Body **bold** `code`")
        let bold = try XCTUnwrap(attributes(in: string, at: "bold")?[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let code = try XCTUnwrap(attributes(in: string, at: "code")?[.font] as? NSFont)
        XCTAssertEqual(code.familyName, "Menlo")
    }

    /// The paper palette is fixed: dark mode must not hand Word white text.
    func testInksAreFixedForPaper() throws {
        let (string, _) = try roundTrip("Body text.")
        let color = try XCTUnwrap(attributes(in: string, at: "Body")?[.foregroundColor] as? NSColor)
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        XCTAssertLessThan(rgb.redComponent + rgb.greenComponent + rgb.blueComponent, 0.5)
    }

    func testImagesBecomeAlternativeText() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
        let png = NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:])
        try XCTUnwrap(png).write(to: folder.appendingPathComponent("dot.png"))

        let (string, _) = try roundTrip("![A red dot](dot.png) and ![](remote.png)", baseURL: folder)
        XCTAssertTrue(string.string.contains("[A red dot]"))
        XCTAssertTrue(string.string.contains("[remote.png]"))
        var attachments = 0
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertEqual(attachments, 0)
    }

    func testFrontMatterIsOmitted() throws {
        let (string, _) = try roundTrip("---\ntitle: x\n---\n# Doc")
        XCTAssertFalse(string.string.contains("title: x"))
        XCTAssertTrue(string.string.contains("Doc"))
    }

    func testTitleGoesToDocumentInfo() throws {
        let (_, info) = try roundTrip("Hola", title: "Notas")
        XCTAssertEqual(info[.title] as? String, "Notas")
    }

    /// The preview itself keeps embedding images: the option is opt-in.
    func testPreviewDefaultStillEmbedsImages() {
        XCTAssertFalse(PreviewRenderOptions().imagesAsText)
    }
}
