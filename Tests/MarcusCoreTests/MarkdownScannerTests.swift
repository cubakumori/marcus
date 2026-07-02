import XCTest
@testable import MarcusCore

final class MarkdownScannerTests: XCTestCase {

    private func kinds(_ text: String) -> [LineKind] {
        MarkdownScanner.scan(text).lines.map(\.kind)
    }

    // MARK: - Line classification

    func testEmptyDocumentIsSingleBlankLine() {
        XCTAssertEqual(kinds(""), [.blank])
    }

    func testHeadingLevels() {
        XCTAssertEqual(kinds("# H1"), [.heading(level: 1)])
        XCTAssertEqual(kinds("###### H6"), [.heading(level: 6)])
        XCTAssertEqual(kinds("####### too deep"), [.paragraph])
        XCTAssertEqual(kinds("#no-space"), [.paragraph])
        XCTAssertEqual(kinds("##"), [.heading(level: 2)])
    }

    func testFencedCodeBlock() {
        let text = "```swift\nlet x = 1\n```\ntext"
        XCTAssertEqual(kinds(text), [.fenceDelimiter, .fencedCode, .fenceDelimiter, .paragraph])
    }

    func testUnclosedFenceExtendsToEnd() {
        let text = "```\ncode\nstill code"
        XCTAssertEqual(kinds(text), [.fenceDelimiter, .fencedCode, .fencedCode])
    }

    func testFenceCloseRequiresAtLeastOpeningLength() {
        let text = "````\n```\n````"
        XCTAssertEqual(kinds(text), [.fenceDelimiter, .fencedCode, .fenceDelimiter])
    }

    func testMarkdownSyntaxInsideFenceIsCode() {
        let text = "```\n# not a heading\n- not a list\n```"
        XCTAssertEqual(kinds(text), [.fenceDelimiter, .fencedCode, .fencedCode, .fenceDelimiter])
    }

    func testTildeFence() {
        XCTAssertEqual(kinds("~~~\ncode\n~~~"), [.fenceDelimiter, .fencedCode, .fenceDelimiter])
    }

    func testThematicBreakVersusList() {
        XCTAssertEqual(kinds("---"), [.thematicBreak])
        XCTAssertEqual(kinds("- - -"), [.thematicBreak])
        XCTAssertEqual(kinds("* * *"), [.thematicBreak])
        XCTAssertEqual(kinds("- item"), [.listItem])
        XCTAssertEqual(kinds("--"), [.paragraph])
    }

    func testLists() {
        XCTAssertEqual(kinds("- one"), [.listItem])
        XCTAssertEqual(kinds("+ one"), [.listItem])
        XCTAssertEqual(kinds("* one"), [.listItem])
        XCTAssertEqual(kinds("1. one"), [.listItem])
        XCTAssertEqual(kinds("42) one"), [.listItem])
        XCTAssertEqual(kinds("-no space"), [.paragraph])
        XCTAssertEqual(kinds("1.no space"), [.paragraph])
    }

    func testBlockquote() {
        XCTAssertEqual(kinds("> quoted"), [.blockquote])
    }

    func testIndentedCodeVersusLazyContinuation() {
        XCTAssertEqual(kinds("\n    code"), [.blank, .indentedCode])
        XCTAssertEqual(kinds("paragraph\n    continuation"), [.paragraph, .paragraph])
    }

    func testBlankLines() {
        XCTAssertEqual(kinds("a\n\nb"), [.paragraph, .blank, .paragraph])
        XCTAssertEqual(kinds("   \t "), [.blank])
    }

    func testTrailingNewlineProducesFinalBlankLine() {
        XCTAssertEqual(kinds("a\n"), [.paragraph, .blank])
    }

    // MARK: - Ranges

    func testRangesExcludeLineTerminators() {
        let scan = MarkdownScanner.scan("ab\ncd")
        XCTAssertEqual(scan.lines[0].range, NSRange(location: 0, length: 2))
        XCTAssertEqual(scan.lines[1].range, NSRange(location: 3, length: 2))
    }

    func testCRLFRanges() {
        let scan = MarkdownScanner.scan("ab\r\ncd")
        XCTAssertEqual(scan.lines[0].range, NSRange(location: 0, length: 2))
        XCTAssertEqual(scan.lines[1].range, NSRange(location: 4, length: 2))
    }

    // MARK: - Inline spans

    private func spans(_ line: String) -> [InlineSpan] {
        MarkdownScanner.scan(line).lines[0].spans
    }

    func testInlineCodeSpan() {
        let result = spans("a `code` b")
        XCTAssertTrue(result.contains(InlineSpan(range: NSRange(location: 2, length: 6), kind: .code)))
    }

    func testUnmatchedBacktickHasNoCodeSpan() {
        XCTAssertFalse(spans("a `code b").contains { $0.kind == .code })
    }

    func testStrongAndEmphasis() {
        XCTAssertTrue(spans("**bold**").contains(InlineSpan(range: NSRange(location: 0, length: 8), kind: .strong)))
        XCTAssertTrue(spans("*it*").contains(InlineSpan(range: NSRange(location: 0, length: 4), kind: .emphasis)))
        XCTAssertTrue(spans("__bold__").contains(InlineSpan(range: NSRange(location: 0, length: 8), kind: .strong)))
        XCTAssertFalse(spans("2 * 3 * 4").contains { $0.kind == .emphasis })
    }

    func testEmphasisIgnoredInsideCodeSpan() {
        XCTAssertFalse(spans("`*not emphasis*`").contains { $0.kind == .emphasis })
    }

    func testLinkSpans() {
        let result = spans("see [text](https://example.com) end")
        XCTAssertTrue(result.contains(InlineSpan(range: NSRange(location: 4, length: 6), kind: .linkText)))
        XCTAssertTrue(result.contains(InlineSpan(range: NSRange(location: 10, length: 21), kind: .linkURL)))
    }

    func testHeadingMarkerSpan() {
        let result = spans("## title")
        XCTAssertTrue(result.contains(InlineSpan(range: NSRange(location: 0, length: 2), kind: .marker)))
    }

    func testInlineSpansInsideHeading() {
        XCTAssertTrue(spans("# a **b**").contains { $0.kind == .strong })
    }

    func testListMarkerSpan() {
        XCTAssertTrue(spans("- item").contains(InlineSpan(range: NSRange(location: 0, length: 1), kind: .marker)))
        XCTAssertTrue(spans("12. item").contains(InlineSpan(range: NSRange(location: 0, length: 3), kind: .marker)))
    }

    // MARK: - Content equality (incremental diffing)

    func testContentEqualsIgnoresAbsolutePosition() {
        let a = MarkdownScanner.scan("x\n# title").lines[1]
        let b = MarkdownScanner.scan("xyz\n# title").lines[1]
        XCTAssertTrue(a.contentEquals(b))
    }

    func testContentEqualsDetectsKindChange() {
        let a = MarkdownScanner.scan("# title").lines[0]
        let b = MarkdownScanner.scan("## title").lines[0]
        XCTAssertFalse(a.contentEquals(b))
    }
}
