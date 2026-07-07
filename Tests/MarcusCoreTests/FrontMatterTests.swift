import XCTest
@testable import MarcusCore

/// Fase 7 (D16): positional YAML front matter — line 1 exactly «---» up to
/// the first later line exactly «---». No YAML parsing, no validation.
final class FrontMatterTests: XCTestCase {

    private func kinds(_ text: String) -> [LineKind] {
        MarkdownScanner.scan(text).lines.map(\.kind)
    }

    // MARK: - Scanner classification

    func testBlockIsClassifiedFrontMatter() {
        let text = "---\ntitle: x\n---\n# Real"
        XCTAssertEqual(kinds(text), [.frontMatter, .frontMatter, .frontMatter, .heading(level: 1)])
    }

    func testWithoutClosingThereIsNoFrontMatter() {
        let text = "---\ntitle: x\n# H"
        XCTAssertEqual(kinds(text), [.thematicBreak, .paragraph, .heading(level: 1)])
    }

    func testOpenerMustBeExactlyThreeDashes() {
        XCTAssertEqual(kinds("----\na\n---")[0], .thematicBreak)
        XCTAssertEqual(kinds("--- \na\n---")[0], .thematicBreak)
        XCTAssertEqual(kinds(" ---\na\n---")[0], .thematicBreak)
    }

    func testCloserMustBeExactlyThreeDashes() {
        // "--- " does not close; the later exact "---" does.
        let text = "---\na: 1\n--- \nb: 2\n---\ntext"
        XCTAssertEqual(kinds(text), [
            .frontMatter, .frontMatter, .frontMatter, .frontMatter, .frontMatter, .paragraph,
        ])
    }

    func testInsideIsNotScannedAsMarkdown() {
        let text = "---\n# not a heading\n- not a list\n```\n---\n# yes"
        let scan = MarkdownScanner.scan(text)
        XCTAssertEqual(scan.lines.map(\.kind), [
            .frontMatter, .frontMatter, .frontMatter, .frontMatter, .frontMatter, .heading(level: 1),
        ])
        // Metadata is dimmed as a whole: no inline spans, and the "```"
        // inside must not leak an open fence past the block.
        XCTAssertTrue(scan.lines.prefix(5).allSatisfy { $0.spans.isEmpty })
    }

    func testEmptyBlock() {
        XCTAssertEqual(kinds("---\n---\ntext"), [.frontMatter, .frontMatter, .paragraph])
    }

    func testDashesLineLaterInDocumentStaysThematicBreak() {
        let text = "---\na: 1\n---\ntext\n---"
        XCTAssertEqual(kinds(text).last, .thematicBreak)
    }

    func testSetextUnderlineIsNotAnOpener() {
        // First line is text, not «---»: the classic setext heading stays.
        let text = "Título\n---"
        XCTAssertEqual(kinds(text), [.paragraph, .thematicBreak])
    }

    func testCRLF() {
        let text = "---\r\ntitle: x\r\n---\r\n# Real"
        XCTAssertEqual(kinds(text), [.frontMatter, .frontMatter, .frontMatter, .heading(level: 1)])
    }

    // MARK: - Incremental rescan falls back to a full scan around the block

    private func assertRescanMatchesFullScan(
        base: String, editedRange: NSRange, replacement: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let old = MarkdownScanner.scan(base)
        let new = (base as NSString).replacingCharacters(in: editedRange, with: replacement)
        let delta = (replacement as NSString).length - editedRange.length
        let newRange = NSRange(location: editedRange.location, length: (replacement as NSString).length)
        let (incremental, dirty) = MarkdownScanner.rescan(
            after: old, editedRange: newRange, delta: delta, in: new)
        let full = MarkdownScanner.scan(new)
        XCTAssertEqual(incremental.lines, full.lines, file: file, line: line)
        // Every line whose kind or content changed must be reported dirty.
        for (index, fullLine) in full.lines.enumerated()
        where index < old.lines.count && !fullLine.contentEquals(old.lines[index]) {
            XCTAssertTrue(dirty.contains(index), "line \(index) not dirty", file: file, line: line)
        }
    }

    func testEditInsideBlockKeepsClassification() {
        assertRescanMatchesFullScan(
            base: "---\ntitle: x\n---\n# Real",
            editedRange: NSRange(location: 10, length: 0), replacement: "y")
    }

    func testDeletingCloserDissolvesTheBlock() {
        // Removing the closing «---» turns the whole prefix back into Markdown.
        assertRescanMatchesFullScan(
            base: "---\ntitle: x\n---\n# Real",
            editedRange: NSRange(location: 13, length: 4), replacement: "")
    }

    func testTypingCloserCreatesTheBlock() {
        // "---\ntitle: x\ntext" has no block; typing «---\n» in the middle closes one.
        assertRescanMatchesFullScan(
            base: "---\ntitle: x\ntext",
            editedRange: NSRange(location: 13, length: 0), replacement: "---\n")
    }

    func testAddingOpenerCreatesTheBlock() {
        assertRescanMatchesFullScan(
            base: "title: x\n---\ntext",
            editedRange: NSRange(location: 0, length: 0), replacement: "---\n")
    }

    func testEditFarBelowFrontMatterDocument() {
        assertRescanMatchesFullScan(
            base: "---\ntitle: x\n---\n# Real\n\ntexto",
            editedRange: NSRange(location: 25, length: 0), replacement: "más ")
    }

    // MARK: - FrontMatter.block(in:) (the consumers' trim helper)

    func testBlockLengthAndLineCount() {
        let text = "---\na: b\n---\nrest"
        let block = FrontMatter.block(in: text)
        XCTAssertEqual(block?.lineCount, 3)
        XCTAssertEqual(block?.utf16Length, 13)
        XCTAssertEqual((text as NSString).substring(from: block!.utf16Length), "rest")
    }

    func testBlockAtEndOfFileWithoutTrailingNewline() {
        let text = "---\na: b\n---"
        let block = FrontMatter.block(in: text)
        XCTAssertEqual(block?.lineCount, 3)
        XCTAssertEqual(block?.utf16Length, (text as NSString).length)
    }

    func testBlockCRLFLength() {
        let text = "---\r\na: b\r\n---\r\nrest"
        let block = FrontMatter.block(in: text)
        XCTAssertEqual(block?.lineCount, 3)
        XCTAssertEqual((text as NSString).substring(from: block!.utf16Length), "rest")
    }

    func testNoBlock() {
        XCTAssertNil(FrontMatter.block(in: ""))
        XCTAssertNil(FrontMatter.block(in: "# doc"))
        XCTAssertNil(FrontMatter.block(in: "---\nunclosed"))
        XCTAssertNil(FrontMatter.block(in: "---"))
        XCTAssertNil(FrontMatter.block(in: "text\n---\na\n---"))
    }

    // MARK: - Outline ignores the block

    func testOutlineIgnoresFrontMatter() {
        let text = "---\n# key: value\n---\n# Real"
        let scan = MarkdownScanner.scan(text)
        let items = MarkdownOutline.items(from: scan, in: text)
        XCTAssertEqual(items.map(\.title), ["Real"])
    }
}
