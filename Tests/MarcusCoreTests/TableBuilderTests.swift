import XCTest
@testable import MarcusCore

final class TableBuilderTests: XCTestCase {

    private func header(_ n: Int) -> String { "Column \(n)" }

    // MARK: Building

    func testBuildsAnAlignedEmptyTable() {
        XCTAssertEqual(TableBuilder.table(rows: 2, columns: 3, header: header), [
            "| Column 1 | Column 2 | Column 3 |",
            "| -------- | -------- | -------- |",
            "|          |          |          |",
            "|          |          |          |",
        ])
    }

    func testCountsAreClampedToOne() {
        XCTAssertEqual(TableBuilder.table(rows: 0, columns: 0, header: header),
                       ["| Column 1 |", "| -------- |", "|          |"])
    }

    // MARK: Insertion

    private func insert(_ text: String, at offset: Int) -> TableBuilder.Insertion {
        TableBuilder.insertion(in: text, at: offset, rows: 1, columns: 2, header: header)
    }

    private let table = "| Column 1 | Column 2 |\n| -------- | -------- |\n|          |          |"

    func testInsertionInAnEmptyDocument() {
        let insertion = insert("", at: 0)
        XCTAssertEqual(insertion.replacement, table + "\n")
        XCTAssertEqual(insertion.selection, NSRange(location: 2, length: 8))
    }

    func testInsertionAfterAParagraphAddsBlankLinesAround() {
        let text = "Intro.\nAfter."
        let insertion = insert(text, at: 6)
        // The newline already there after the caret counts as one of the two.
        XCTAssertEqual(insertion.replacement, "\n\n" + table + "\n")
        XCTAssertEqual(insertion.selection, NSRange(location: 4, length: 8))
        let result = (text as NSString).replacingCharacters(in: NSRange(location: 6, length: 0), with: insertion.replacement)
        XCTAssertEqual(result, "Intro.\n\n" + table + "\n\nAfter.")
    }

    func testInsertionOnABlankLineBetweenParagraphsAddsNothingExtra() {
        let text = "Intro.\n\n\nAfter."
        let insertion = insert(text, at: 8)
        XCTAssertEqual(insertion.replacement, table + "\n")
        let result = (text as NSString).replacingCharacters(in: NSRange(location: 8, length: 0), with: insertion.replacement)
        XCTAssertEqual(result, "Intro.\n\n" + table + "\n\nAfter.")
    }

    func testInsertionAtTheStartOfALineAddsOneBlankLineBefore() {
        let text = "Intro.\nAfter."
        let insertion = insert(text, at: 7)
        XCTAssertEqual(insertion.replacement, "\n" + table + "\n\n")
    }

    func testInsertionAtTheEndOfTextEndsWithOneNewline() {
        let insertion = insert("Intro.", at: 6)
        XCTAssertEqual(insertion.replacement, "\n\n" + table + "\n")
    }

    func testInsertionRespectsCRLF() {
        let insertion = insert("Intro.\r\n", at: 8)
        XCTAssertEqual(insertion.replacement, "\r\n" + table.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n")
    }

    func testSelectionCoversTheFirstHeaderCell() {
        let text = "Intro."
        let insertion = insert(text, at: 6)
        let result = (text as NSString).replacingCharacters(in: NSRange(location: 6, length: 0), with: insertion.replacement)
        let absolute = NSRange(location: 6 + insertion.selection.location, length: insertion.selection.length)
        XCTAssertEqual((result as NSString).substring(with: absolute), "Column 1")
    }
}

final class TableCellMoveTests: XCTestCase {

    private let text = "x\n\n|a|bb|\n|-|-|\n|1|hello|\n|2|3|\n\ny"

    private func offset(of needle: String) -> Int { (text as NSString).range(of: needle).location }

    private func selected(_ move: TableFormatter.CellMove) -> String {
        let result = (text as NSString).replacingCharacters(in: move.edit.range, with: move.edit.replacement)
        return (result as NSString).substring(with: move.selection)
    }

    func testTabSelectsTheNextCell() throws {
        let move = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "a|bb"), forward: true))
        XCTAssertEqual(selected(move), "bb")
        XCTAssertEqual(move.edit.replacement, "| a   | bb    |\n| --- | ----- |\n| 1   | hello |\n| 2   | 3     |")
    }

    func testTabFromTheLastHeaderCellSkipsTheDelimiterRow() throws {
        let move = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "bb"), forward: true))
        XCTAssertEqual(selected(move), "1")
    }

    func testTabFromTheDelimiterRowGoesToTheFirstBodyCell() throws {
        let move = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "|-|-|") + 1, forward: true))
        XCTAssertEqual(selected(move), "1")
    }

    func testTabWrapsToTheNextRow() throws {
        let move = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "hello"), forward: true))
        XCTAssertEqual(selected(move), "2")
    }

    func testTabOnTheLastCellAppendsARow() throws {
        let move = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "|2|3|") + 3, forward: true))
        XCTAssertEqual(move.edit.replacement, "| a   | bb    |\n| --- | ----- |\n| 1   | hello |\n| 2   | 3     |\n|     |       |")
        XCTAssertEqual(move.selection.length, 0)
        let result = (text as NSString).replacingCharacters(in: move.edit.range, with: move.edit.replacement) as NSString
        XCTAssertEqual(result.substring(with: NSRange(location: move.selection.location - 2, length: 2)), "| ")
        XCTAssertTrue(result.substring(from: move.selection.location).hasPrefix("    |       |\n\ny"))
    }

    func testTabWithOnlyAHeaderAppendsTheFirstBodyRow() throws {
        let headerOnly = "|a|b|\n|-|-|"
        let move = try XCTUnwrap(TableFormatter.moveCell(in: headerOnly, caretAt: 3, forward: true))
        XCTAssertEqual(move.edit.replacement, "| a   | b   |\n| --- | --- |\n|     |     |")
    }

    func testShiftTabSelectsThePreviousCellAndWrapsUp() throws {
        let back = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "hello"), forward: false))
        XCTAssertEqual(selected(back), "1")
        let up = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "|1|") + 1, forward: false))
        XCTAssertEqual(selected(up), "bb", "skips the delimiter row")
        let stay = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "a|bb"), forward: false))
        XCTAssertEqual(selected(stay), "a")
    }

    func testShiftTabFromTheDelimiterRowGoesToTheHeaderCellAbove() throws {
        let move = try XCTUnwrap(TableFormatter.moveCell(in: text, caretAt: offset(of: "|-|-|") + 3, forward: false))
        XCTAssertEqual(selected(move), "bb")
    }

    func testOutsideATableThereIsNoMove() {
        XCTAssertNil(TableFormatter.moveCell(in: text, caretAt: 0, forward: true))
        XCTAssertNil(TableFormatter.moveCell(in: text, caretAt: (text as NSString).length, forward: false))
        XCTAssertFalse(TableFormatter.isInTable(text, caretAt: 0))
        XCTAssertTrue(TableFormatter.isInTable(text, caretAt: offset(of: "hello")))
    }
}
