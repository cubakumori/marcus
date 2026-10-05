import XCTest
@testable import MarcusCore

final class TextAppendTests: XCTestCase {

    func testAppendsOnANewLineAndKeepsTheTrailingNewline() {
        XCTAssertEqual(TextAppend.appended("more", to: "one\n", onNewLine: true), "one\nmore\n")
        XCTAssertEqual(TextAppend.appended("more", to: "one", onNewLine: true), "one\nmore")
    }

    func testAppendsInlineWhenAsked() {
        XCTAssertEqual(TextAppend.appended(" more", to: "one", onNewLine: false), "one more")
        XCTAssertEqual(TextAppend.appended(" more", to: "one\n", onNewLine: false), "one\n more\n")
    }

    func testNoDoubleNewlineWhenTheOriginalAlreadyEndsWithOne() {
        XCTAssertEqual(TextAppend.appended("more\n", to: "one\n", onNewLine: true), "one\nmore\n")
    }

    func testTextEndingWithNewlineDoesNotForceOneOnAFileWithout() {
        XCTAssertEqual(TextAppend.appended("more\n", to: "one", onNewLine: true), "one\nmore")
    }

    func testEmptyOriginalTakesTheTextWithAFinalNewline() {
        XCTAssertEqual(TextAppend.appended("note", to: "", onNewLine: true), "note\n")
        XCTAssertEqual(TextAppend.appended("note\n", to: "", onNewLine: false), "note\n")
    }

    func testIncomingWindowsLineEndingsAreNormalized() {
        XCTAssertEqual(TextAppend.appended("a\r\nb", to: "one\n", onNewLine: true), "one\na\nb\n")
    }

    func testMultiLineAppend() {
        XCTAssertEqual(TextAppend.appended("- x\n- y", to: "# List\n", onNewLine: true), "# List\n- x\n- y\n")
    }
}
