import XCTest
@testable import MarcusCore

final class TableFormatterTests: XCTestCase {

    private func formatted(_ markdown: String) -> String {
        TableFormatter.formattedLines(markdown.components(separatedBy: "\n")).joined(separator: "\n")
    }

    // MARK: Formatting

    func testPadsColumnsAndNormalizesPipes() {
        let input = "a|bb|ccc\n-|-|-\n1|22|3"
        XCTAssertEqual(formatted(input), """
        | a   | bb  | ccc |
        | --- | --- | --- |
        | 1   | 22  | 3   |
        """)
    }

    func testKeepsAlignmentMarkersAndAlignsCells() {
        let input = "| Left | Center | Right |\n|:--|:-:|--:|\n| a | b | c |\n| longer | mid | 12345 |"
        XCTAssertEqual(formatted(input), """
        | Left   | Center | Right |
        | :----- | :----: | ----: |
        | a      |   b    |     c |
        | longer |  mid   | 12345 |
        """)
    }

    func testMinimumColumnWidthIsThree() {
        XCTAssertEqual(formatted("a|b\n-|-\n1|2"), "| a   | b   |\n| --- | --- |\n| 1   | 2   |")
        // The header follows its column's alignment too.
        XCTAssertEqual(formatted("a|b\n:-:|-:\n1|2"), "|  a  |   b |\n| :-: | --: |\n|  1  |   2 |")
    }

    func testShortRowsArePaddedWithEmptyCellsNeverTrimmed() {
        let input = "| a | b | c |\n|---|---|\n| 1 |\n| x | y | z | extra |"
        XCTAssertEqual(formatted(input), """
        | a   | b   | c   |       |
        | --- | --- | --- | ----- |
        | 1   |     |     |       |
        | x   | y   | z   | extra |
        """)
    }

    func testEscapedPipesStayInsideTheirCell() {
        let input = "| a \\| b | c |\n|---|---|\n| x | y |"
        XCTAssertEqual(formatted(input), "| a \\| b | c   |\n| ------ | --- |\n| x      | y   |")
    }

    func testWideCharactersCountTwoColumns() {
        XCTAssertEqual(TableFormatter.displayWidth("日本"), 4)
        XCTAssertEqual(TableFormatter.displayWidth("café"), 4)
        XCTAssertEqual(TableFormatter.displayWidth("e\u{301}"), 1)
        XCTAssertEqual(TableFormatter.displayWidth("👍"), 2)
        XCTAssertEqual(formatted("| 日本 | b |\n|---|---|\n| ab | c |"), "| 日本 | b   |\n| ---- | --- |\n| ab   | c   |")
    }

    func testAlreadyFormattedTableIsStable() {
        let table = "| a   | b   |\n| --- | --- |\n| 1   | 2   |"
        XCTAssertEqual(formatted(table), table)
        XCTAssertEqual(formatted(formatted("x|yy\n-|-\n1|2")), formatted("x|yy\n-|-\n1|2"))
    }

    func testInlineCodeAndLinksAreJustText() {
        let input = "| `code` | [l](u) |\n|---|---|\n| a | b |"
        XCTAssertEqual(formatted(input), "| `code` | [l](u) |\n| ------ | ------ |\n| a      | b      |")
    }

    // MARK: Finding the table under the caret

    private let document = """
    # Title

    Intro paragraph.

    | a | b |
    |---|--:|
    | 1 | 2 |
    | three | 4 |

    After.

    ```
    | not | a table |
    |---|---|
    ```

    x | y
    - | -
    """

    private func offset(of needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    func testFindsTheTableAroundTheCaret() throws {
        let caret = offset(of: "three", in: document) + 2
        let edit = try XCTUnwrap(TableFormatter.edit(in: document, caretAt: caret))
        let ns = document as NSString
        XCTAssertEqual(ns.substring(with: edit.range), "| a | b |\n|---|--:|\n| 1 | 2 |\n| three | 4 |")
        XCTAssertEqual(edit.replacement, "| a     |   b |\n| ----- | --: |\n| 1     |   2 |\n| three |   4 |")
    }

    func testCaretOnHeaderAndDelimiterRowsQualifies() {
        XCTAssertNotNil(TableFormatter.edit(in: document, caretAt: offset(of: "| a | b |", in: document)))
        XCTAssertNotNil(TableFormatter.edit(in: document, caretAt: offset(of: "|---|--:|", in: document) + 3))
    }

    func testCaretOutsideTablesFindsNothing() {
        XCTAssertNil(TableFormatter.edit(in: document, caretAt: 0))
        XCTAssertNil(TableFormatter.edit(in: document, caretAt: offset(of: "Intro", in: document)))
        XCTAssertNil(TableFormatter.edit(in: document, caretAt: offset(of: "After", in: document)))
        XCTAssertNil(TableFormatter.edit(in: "", caretAt: 0))
        XCTAssertNil(TableFormatter.edit(in: "just | pipes\nno delimiter | row", caretAt: 2))
    }

    func testFencedCodeIsLeftAlone() {
        XCTAssertNil(TableFormatter.edit(in: document, caretAt: offset(of: "| not | a table |", in: document) + 3))
    }

    func testFrontMatterIsLeftAlone() {
        let text = "---\ntitle: a | b\n---\n| a | b |\n|---|---|\n| 1 | 2 |"
        XCTAssertNil(TableFormatter.edit(in: text, caretAt: 6))
        XCTAssertNotNil(TableFormatter.edit(in: text, caretAt: offset(of: "| 1 |", in: text)))
    }

    func testTableWithoutOuterPipesAtTheEndOfText() throws {
        let edit = try XCTUnwrap(TableFormatter.edit(in: document, caretAt: offset(of: "x | y", in: document) + 1))
        XCTAssertEqual(edit.replacement, "| x   | y   |\n| --- | --- |")
        XCTAssertEqual(edit.range.upperBound, (document as NSString).length)
    }

    func testParagraphWithAPipeAboveTheHeaderIsNotPartOfTheTable() throws {
        let text = "either | or\n| a | b |\n|---|---|\n| 1 | 2 |"
        let edit = try XCTUnwrap(TableFormatter.edit(in: text, caretAt: offset(of: "| 1 |", in: text)))
        XCTAssertEqual(edit.range.location, offset(of: "| a | b |", in: text))
        // From the stray line itself there is no table: it is above the header.
        XCTAssertNil(TableFormatter.edit(in: text, caretAt: 2))
    }

    func testCRLFIsPreserved() throws {
        let text = "| a | b |\r\n|---|---|\r\n| 1 | 2 |\r\n"
        let edit = try XCTUnwrap(TableFormatter.edit(in: text, caretAt: 1))
        XCTAssertEqual(edit.replacement, "| a   | b   |\r\n| --- | --- |\r\n| 1   | 2   |")
    }

    // MARK: Caret

    func testCaretStaysInItsCellAtTheSameOffset() throws {
        let text = "|a|bb|\n|-|-|\n|1|hello|"
        // Caret after "hel" in the last row.
        let caret = offset(of: "hello", in: text) + 3
        let edit = try XCTUnwrap(TableFormatter.edit(in: text, caretAt: caret))
        let formatted = edit.replacement as NSString
        XCTAssertEqual(formatted.substring(to: edit.caretOffset).hasSuffix("| 1   | hel"), true, edit.replacement)
    }

    func testCaretInHeaderAndDelimiterRows() throws {
        let text = "|a|bb|\n|-|-|\n|1|2|"
        let header = try XCTUnwrap(TableFormatter.edit(in: text, caretAt: offset(of: "bb", in: text) + 1))
        XCTAssertTrue((header.replacement as NSString).substring(to: header.caretOffset).hasSuffix("| a   | b"))
        let delimiter = try XCTUnwrap(TableFormatter.edit(in: text, caretAt: offset(of: "|-|-|", in: text) + 3))
        XCTAssertTrue((delimiter.replacement as NSString).substring(to: delimiter.caretOffset).hasSuffix("| --- | "))
    }

    func testCaretPastTheLastCellClampsToItsEnd() throws {
        let text = "| a | b |\n|---|---|\n| 1 | 22 |   "
        let edit = try XCTUnwrap(TableFormatter.edit(in: text, caretAt: (text as NSString).length))
        XCTAssertTrue((edit.replacement as NSString).substring(to: edit.caretOffset).hasSuffix("| 22"))
    }
}
