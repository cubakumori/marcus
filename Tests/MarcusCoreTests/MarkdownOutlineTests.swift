import XCTest
@testable import MarcusCore

final class MarkdownOutlineTests: XCTestCase {

    private func outline(_ text: String) -> [OutlineItem] {
        MarkdownOutline.items(from: MarkdownScanner.scan(text), in: text)
    }

    func testExtractsHeadingsWithLevels() {
        let items = outline("# One\n\npara\n\n## Two\n\n### Three\n")
        XCTAssertEqual(items.map(\.level), [1, 2, 3])
        XCTAssertEqual(items.map(\.title), ["One", "Two", "Three"])
    }

    func testTitleStripsBoldAndItalicMarkers() {
        let items = outline("# **Bold** and *italic* title")
        XCTAssertEqual(items.first?.title, "Bold and italic title")
    }

    func testInlineCodeIsKeptVerbatim() {
        // v1: code spans keep their backticks; only markers are stripped.
        let items = outline("## Use `swift build`")
        XCTAssertEqual(items.first?.title, "Use `swift build`")
    }

    func testClosingHashSequenceIsStripped() {
        XCTAssertEqual(outline("## Title ##").first?.title, "Title")
    }

    func testTrailingHashWithoutSpaceIsContent() {
        XCTAssertEqual(outline("## Learning C#").first?.title, "Learning C#")
    }

    func testHeadingsInsideCodeFencesAreIgnored() {
        let items = outline("```\n# not a heading\n```\n\n# real\n")
        XCTAssertEqual(items.map(\.title), ["real"])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertTrue(outline("#nospace\n").isEmpty)
    }

    func testRangeTargetsTheHeadingLine() {
        let text = "intro\n\n## Second section\n\nbody\n"
        let items = outline(text)
        XCTAssertEqual(items.count, 1)
        let line = (text as NSString).substring(with: items[0].range)
        XCTAssertTrue(line.contains("## Second section"))
    }

    func testEmptyDocumentHasNoItems() {
        XCTAssertTrue(outline("").isEmpty)
    }
}
