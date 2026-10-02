import XCTest
import AppKit
@testable import MarcusPreview

final class PreviewImageCacheTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("marcus-image-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        PreviewImageCache.shared.removeAll()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A tiny PNG on disk (size 4×4).
    private func writePNG(named name: String) throws -> URL {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let url = folder.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    private func render() -> NSAttributedString {
        MarkdownPreviewRenderer.render("![pic](pic.png)", options: PreviewRenderOptions(baseURL: folder)).string
    }

    private func hasAttachment(_ rendered: NSAttributedString) -> Bool {
        var found = false
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value is NSTextAttachment { found = true }
        }
        return found
    }

    func testSecondRenderReusesTheDecodedImage() throws {
        _ = try writePNG(named: "pic.png")
        XCTAssertTrue(hasAttachment(render()))
        XCTAssertTrue(hasAttachment(render()))
        XCTAssertEqual(PreviewImageCache.shared.loadCount, 1)
    }

    func testModifiedFileIsDecodedAgain() throws {
        let url = try writePNG(named: "pic.png")
        _ = render()
        // Same bytes, newer modification date: the file "changed".
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        _ = render()
        XCTAssertEqual(PreviewImageCache.shared.loadCount, 2)
    }

    func testMissingFileRendersPlaceholderWithoutCaching() {
        let rendered = render()
        XCTAssertFalse(hasAttachment(rendered))
        XCTAssertTrue(rendered.string.contains("pic.png"))
        XCTAssertEqual(PreviewImageCache.shared.loadCount, 0)
    }
}
