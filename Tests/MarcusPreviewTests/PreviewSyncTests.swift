import XCTest
@testable import MarcusPreview

final class PreviewSyncTests: XCTestCase {

    // MARK: - Anchor emission (renderer)

    func testRendererEmitsOneAnchorPerHeading() {
        let rendered = MarkdownPreviewRenderer.render("# One\n\ntext\n\n## Two\n\nmore\n")
        XCTAssertEqual(rendered.anchors.map(\.sourceLine), [1, 5])
    }

    func testAnchorLocationsPointAtRenderedHeadings() {
        let rendered = MarkdownPreviewRenderer.render("# One\n\ntext\n\n## Two\n\nmore\n")
        let text = rendered.string.string as NSString
        XCTAssertEqual(rendered.anchors.count, 2)
        XCTAssertTrue(text.substring(from: rendered.anchors[0].location).hasPrefix("One"))
        XCTAssertTrue(text.substring(from: rendered.anchors[1].location).hasPrefix("Two"))
    }

    func testAnchorsAreOrderedByRenderedLocation() {
        let markdown = (1...6).map { "## H\($0)\n\npárrafo\n" }.joined(separator: "\n")
        let rendered = MarkdownPreviewRenderer.render(markdown)
        XCTAssertEqual(rendered.anchors.count, 6)
        XCTAssertEqual(rendered.anchors.map(\.location), rendered.anchors.map(\.location).sorted())
        XCTAssertEqual(rendered.anchors.map(\.sourceLine), rendered.anchors.map(\.sourceLine).sorted())
    }

    func testSetextHeadingAnchorsToItsTextLine() {
        let rendered = MarkdownPreviewRenderer.render("intro\n\nTitle\n=====\n\ntext\n")
        XCTAssertEqual(rendered.anchors.map(\.sourceLine), [3])
    }

    func testHeadingInsideBlockquoteStillAnchors() {
        let rendered = MarkdownPreviewRenderer.render("> # Quoted\n>\n> body\n")
        XCTAssertEqual(rendered.anchors.map(\.sourceLine), [1])
    }

    func testDocumentWithoutHeadingsHasNoAnchors() {
        let rendered = MarkdownPreviewRenderer.render("just a paragraph\n\nand another\n")
        XCTAssertTrue(rendered.anchors.isEmpty)
    }

    func testConsecutiveHeadingsGetDistinctAnchors() {
        let rendered = MarkdownPreviewRenderer.render("# A\n## B\n")
        XCTAssertEqual(rendered.anchors.map(\.sourceLine), [1, 2])
        XCTAssertNotEqual(rendered.anchors[0].location, rendered.anchors[1].location)
    }

    // MARK: - Caret line → rendered location

    private let anchors = [
        PreviewAnchor(sourceLine: 3, location: 10),
        PreviewAnchor(sourceLine: 8, location: 50),
        PreviewAnchor(sourceLine: 20, location: 200),
    ]

    func testCaretBeforeFirstHeadingGoesToTop() {
        XCTAssertEqual(PreviewSync.location(forSourceLine: 1, anchors: anchors), 0)
        XCTAssertEqual(PreviewSync.location(forSourceLine: 2, anchors: anchors), 0)
    }

    func testCaretOnHeadingLineGoesToItsAnchor() {
        XCTAssertEqual(PreviewSync.location(forSourceLine: 3, anchors: anchors), 10)
        XCTAssertEqual(PreviewSync.location(forSourceLine: 8, anchors: anchors), 50)
    }

    func testCaretInsideSectionGoesToItsHeading() {
        XCTAssertEqual(PreviewSync.location(forSourceLine: 5, anchors: anchors), 10)
        XCTAssertEqual(PreviewSync.location(forSourceLine: 19, anchors: anchors), 50)
    }

    func testCaretPastLastHeadingGoesToLastAnchor() {
        XCTAssertEqual(PreviewSync.location(forSourceLine: 99, anchors: anchors), 200)
    }

    func testNoAnchorsMeansTop() {
        XCTAssertEqual(PreviewSync.location(forSourceLine: 7, anchors: []), 0)
    }
}
