import XCTest
@testable import MarcusCore

final class SelectionWrapTests: XCTestCase {

    func testEachDelimiterWrapsAndKeepsTheSelectionInside() {
        XCTAssertEqual(SelectionWrap.wrap("hola", typing: "*"),
                       .init(replacement: "*hola*", inner: NSRange(location: 1, length: 4)))
        XCTAssertEqual(SelectionWrap.wrap("hola", typing: "_")?.replacement, "_hola_")
        XCTAssertEqual(SelectionWrap.wrap("hola", typing: "`")?.replacement, "`hola`")
        XCTAssertEqual(SelectionWrap.wrap("hola", typing: "~")?.replacement, "~hola~")
        // Brackets close with the matching bracket; the caret-friendly
        // selection is still the text, ready for "](url)" afterwards.
        XCTAssertEqual(SelectionWrap.wrap("hola", typing: "["),
                       .init(replacement: "[hola]", inner: NSRange(location: 1, length: 4)))
    }

    func testOtherKeysTypeAsUsual() {
        XCTAssertNil(SelectionWrap.wrap("hola", typing: "a"))
        XCTAssertNil(SelectionWrap.wrap("hola", typing: "("))
        XCTAssertNil(SelectionWrap.wrap("hola", typing: "\""))
        XCTAssertNil(SelectionWrap.wrap("hola", typing: "**"))  // a paste, not a keystroke
        XCTAssertNil(SelectionWrap.wrap("hola", typing: ""))
        XCTAssertNil(SelectionWrap.wrap("hola", typing: "\n"))
    }

    func testNothingOrOnlyWhitespaceSelectedTypesAsUsual() {
        XCTAssertNil(SelectionWrap.wrap("", typing: "*"))
        XCTAssertNil(SelectionWrap.wrap("   ", typing: "*"))
        XCTAssertNil(SelectionWrap.wrap("\t", typing: "`"))
    }

    func testMultiLineSelectionsTypeAsUsual() {
        XCTAssertNil(SelectionWrap.wrap("una\ndos", typing: "*"))
        XCTAssertNil(SelectionWrap.wrap("una\r\ndos", typing: "*"))
        XCTAssertNil(SelectionWrap.wrap("una\r", typing: "*"))
    }

    func testEdgeWhitespaceStaysOutside() {
        XCTAssertEqual(SelectionWrap.wrap(" hola ", typing: "*"),
                       .init(replacement: " *hola* ", inner: NSRange(location: 2, length: 4)))
        XCTAssertEqual(SelectionWrap.wrap("hola  ", typing: "`")?.replacement, "`hola`  ")
        // Inner spaces are content.
        XCTAssertEqual(SelectionWrap.wrap("hola mundo", typing: "_"),
                       .init(replacement: "_hola mundo_", inner: NSRange(location: 1, length: 10)))
    }

    func testTypingTheKeyAgainNests() {
        // The selection stays on the inner text, so the second keystroke
        // wraps that again: italic → bold, tilde → strikethrough.
        var text = "di hola ya" as NSString
        var selection = NSRange(location: 3, length: 4)
        for _ in 0..<2 {
            let result = SelectionWrap.wrap(text.substring(with: selection), typing: "*")!
            text = text.replacingCharacters(in: selection, with: result.replacement) as NSString
            selection = NSRange(location: selection.location + result.inner.location, length: result.inner.length)
        }
        XCTAssertEqual(text as String, "di **hola** ya")
        XCTAssertEqual(text.substring(with: selection), "hola")
    }

    func testInnerRangeCountsUTF16() {
        let result = SelectionWrap.wrap("😀 ñ", typing: "~")!
        XCTAssertEqual(result.replacement, "~😀 ñ~")
        XCTAssertEqual(result.inner, NSRange(location: 1, length: 4))  // 😀 is two UTF-16 units
        let utf16 = (result.replacement as NSString)
        XCTAssertEqual(utf16.substring(with: result.inner), "😀 ñ")
    }

    func testAlreadyWrappedTextWrapsAgainVerbatim() {
        // No un-wrapping on typing: that is ⌘B / ⌘I's job (EmphasisToggle).
        XCTAssertEqual(SelectionWrap.wrap("*hola*", typing: "*")?.replacement, "**hola**")
    }
}
