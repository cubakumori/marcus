import XCTest
@testable import MarcusCore

final class TextMetricsTests: XCTestCase {

    func testCountsWordsAndCharacters() {
        let counts = TextMetrics.count("Hello brave world")
        XCTAssertEqual(counts.words, 3)
        XCTAssertEqual(counts.characters, 17)
    }

    func testMarkdownMarkersAreNotWords() {
        // Word enumeration skips punctuation-only tokens (#, -, *).
        let counts = TextMetrics.count("## Title\n\n- item\n* other\n")
        XCTAssertEqual(counts.words, 3)
    }

    func testAccentedGraphemesCountOnce() {
        let counts = TextMetrics.count("café con leche")
        XCTAssertEqual(counts.words, 3)
        XCTAssertEqual(counts.characters, 14)
    }

    func testEmptyText() {
        let counts = TextMetrics.count("")
        XCTAssertEqual(counts.words, 0)
        XCTAssertEqual(counts.characters, 0)
    }
}
