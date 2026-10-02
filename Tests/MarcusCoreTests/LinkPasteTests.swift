import XCTest
@testable import MarcusCore

final class LinkPasteTests: XCTestCase {

    private func link(_ selection: String, _ pasted: String) -> String? {
        LinkPaste.replacement(selection: selection, pasted: pasted)
    }

    // MARK: Wraps

    func testWrapsSelectionInLink() {
        XCTAssertEqual(link("Marcus", "https://example.com"), "[Marcus](https://example.com)")
    }

    func testHTTPAndOtherSchemes() {
        XCTAssertEqual(link("a", "http://example.com/x?y=1#z"), "[a](http://example.com/x?y=1#z)")
        XCTAssertEqual(link("write me", "mailto:ana@example.com"), "[write me](mailto:ana@example.com)")
        XCTAssertEqual(link("call", "tel:+34600000000"), "[call](tel:+34600000000)")
        XCTAssertEqual(link("notes", "file:///Users/ana/notes.md"), "[notes](file:///Users/ana/notes.md)")
        XCTAssertEqual(link("ftp", "ftp://files.example.com/a.zip"), "[ftp](ftp://files.example.com/a.zip)")
    }

    func testSchemeIsCaseInsensitiveAndKeptAsPasted() {
        XCTAssertEqual(link("a", "HTTPS://Example.COM/Path"), "[a](HTTPS://Example.COM/Path)")
    }

    func testTrimsWhitespaceAroundPastedURL() {
        // Browsers and chat apps often copy a trailing newline along.
        XCTAssertEqual(link("a", "  https://example.com\n"), "[a](https://example.com)")
    }

    func testMultiWordAndUnicodeSelection() {
        XCTAssertEqual(link("año nuevo chino", "https://e.com"), "[año nuevo chino](https://e.com)")
    }

    func testOuterWhitespaceStaysOutsideTheLink() {
        // A double-click selection often grabs the trailing space.
        XCTAssertEqual(link("word ", "https://e.com"), "[word](https://e.com) ")
        XCTAssertEqual(link("  two words\t", "https://e.com"), "  [two words](https://e.com)\t")
    }

    func testBalancedParenthesesInURLPassThrough() {
        let url = "https://en.wikipedia.org/wiki/Foo_(bar)"
        XCTAssertEqual(link("Foo", url), "[Foo](\(url))")
    }

    func testUnbalancedParenthesesGetAngleBrackets() {
        // CommonMark ends a bare destination at an unbalanced ")"; the
        // pointy form keeps the whole URL.
        XCTAssertEqual(link("x", "https://e.com/a)b"), "[x](<https://e.com/a)b>)")
    }

    func testNonASCIIURL() {
        XCTAssertEqual(link("España", "https://es.wikipedia.org/wiki/España"),
                       "[España](https://es.wikipedia.org/wiki/España)")
    }

    // MARK: Falls back to a normal paste (nil)

    func testPlainTextIsNotALink() {
        XCTAssertNil(link("a", "hello world"))
        XCTAssertNil(link("a", "hello"))
    }

    func testBareDomainWithoutSchemeIsNotALink() {
        // "[a](example.com)" would be a broken relative link.
        XCTAssertNil(link("a", "example.com"))
        XCTAssertNil(link("a", "www.example.com"))
    }

    func testColonInProseIsNotAScheme() {
        XCTAssertNil(link("a", "Hora:tarde"))
        XCTAssertNil(link("a", "12:30"))
    }

    func testUnknownAndUnsafeSchemesAreRejected() {
        XCTAssertNil(link("a", "javascript:alert(1)"))
        XCTAssertNil(link("a", "data:text/html,hi"))
        XCTAssertNil(link("a", "foo://bar"))
    }

    func testURLNeedsAHostOrAnAddress() {
        XCTAssertNil(link("a", "https://"))
        XCTAssertNil(link("a", "https:example.com"))
        XCTAssertNil(link("a", "mailto:"))
    }

    func testWhitespaceInsideIsNotOneURL() {
        XCTAssertNil(link("a", "https://a.com and more"))
        XCTAssertNil(link("a", "https://a.com\nhttps://b.com"))
    }

    func testEmptyOrBlankSelectionIsANormalPaste() {
        XCTAssertNil(link("", "https://e.com"))
        XCTAssertNil(link("   ", "https://e.com"))
    }

    func testMultilineSelectionIsANormalPaste() {
        XCTAssertNil(link("one\ntwo", "https://e.com"))
        XCTAssertNil(link("para\n\npara", "https://e.com"))
    }

    func testSelectionWithBracketsIsANormalPaste() {
        // Would need escaping; not worth guessing — paste as usual.
        XCTAssertNil(link("[a]", "https://e.com"))
        XCTAssertNil(link("a]b", "https://e.com"))
        XCTAssertNil(link("[old](https://old.com)", "https://e.com"))
    }

    func testSelectedURLIsReplacedNotWrapped() {
        // Pasting a URL over a URL: the user is swapping it.
        XCTAssertNil(link("https://old.com", "https://new.com"))
        XCTAssertNil(link(" https://old.com ", "https://new.com"))
    }
}
