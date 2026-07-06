import XCTest
@testable import MarcusCore

final class EmphasisToggleTests: XCTestCase {

    func testWrapsPlainTextInBold() {
        XCTAssertEqual(EmphasisToggle.toggled("word", delimiter: "**"), "**word**")
    }

    func testUnwrapsBold() {
        XCTAssertEqual(EmphasisToggle.toggled("**word**", delimiter: "**"), "word")
    }

    func testWrapsPlainTextInItalic() {
        XCTAssertEqual(EmphasisToggle.toggled("word", delimiter: "*"), "*word*")
    }

    func testUnwrapsItalic() {
        XCTAssertEqual(EmphasisToggle.toggled("*word*", delimiter: "*"), "word")
    }

    func testItalicOnBoldNests() {
        XCTAssertEqual(EmphasisToggle.toggled("**word**", delimiter: "*"), "***word***")
    }

    func testItalicOnBoldItalicRemovesItalic() {
        XCTAssertEqual(EmphasisToggle.toggled("***word***", delimiter: "*"), "**word**")
    }

    func testBoldOnItalicNests() {
        XCTAssertEqual(EmphasisToggle.toggled("*word*", delimiter: "**"), "***word***")
    }

    func testBoldOnBoldItalicRemovesBold() {
        XCTAssertEqual(EmphasisToggle.toggled("***word***", delimiter: "**"), "*word*")
    }

    func testMultiWordSelection() {
        XCTAssertEqual(EmphasisToggle.toggled("two words", delimiter: "**"), "**two words**")
    }

    func testAsymmetricStarsJustWrap() {
        // Not cleanly wrapped: treat as plain content.
        XCTAssertEqual(EmphasisToggle.toggled("*word", delimiter: "*"), "**word*")
    }
}
