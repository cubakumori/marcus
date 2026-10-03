import XCTest
@testable import MarcusCore

final class LinkDestinationTests: XCTestCase {

    private let base = URL(fileURLWithPath: "/Users/ana/Notas", isDirectory: true)

    private func path(_ destination: String) -> String? {
        LinkDestination.url(destination, relativeTo: base)?.standardizedFileURL.path
    }

    func testPlainRelativePath() {
        XCTAssertEqual(path("img/foto.png"), "/Users/ana/Notas/img/foto.png")
    }

    func testPercentEscapesAreDecodedOnce() {
        XCTAssertEqual(path("mi%20foto%20%281%29.png"), "/Users/ana/Notas/mi foto (1).png")
    }

    /// The mix `URL(string:)` gets wrong on its own.
    func testNonASCIIWithPercentEscapes() {
        XCTAssertEqual(path("../Fotos/año/niño%202.jpg"), "/Users/ana/Fotos/año/niño 2.jpg")
    }

    func testRawNonASCIIAndSpaces() {
        XCTAssertEqual(path("diseño final.png"), "/Users/ana/Notas/diseño final.png")
    }

    func testAbsoluteURLsAreKept() {
        XCTAssertEqual(LinkDestination.url("https://example.com/a%20b?q=ñ", relativeTo: base)?.absoluteString,
                       "https://example.com/a%20b?q=%C3%B1")
    }
}
