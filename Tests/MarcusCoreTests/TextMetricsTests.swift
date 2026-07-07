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

    // MARK: - Front matter (Fase 7, D16): metadata is not counted

    func testFrontMatterExcludedFromCounts() {
        // Only "Hola mundo" is the document; the block is metadata.
        let text = "---\ntitle: x\ntags: [a, b]\n---\nHola mundo"
        let counts = TextMetrics.count(text, skippingFrontMatter: true)
        XCTAssertEqual(counts.words, 2)
        XCTAssertEqual(counts.characters, "Hola mundo".count)
    }

    func testFrontMatterCountedWhenNotSkipping() {
        // Default behavior is unchanged: everything counts.
        let text = "---\ntitle: x\n---\nHola mundo"
        XCTAssertEqual(TextMetrics.count(text).words,
                       TextMetrics.count(text, skippingFrontMatter: false).words)
        XCTAssertGreaterThan(TextMetrics.count(text).words, 2)
    }

    func testUnclosedFrontMatterCountsEverythingEvenWhenSkipping() {
        // No closing «---» → no block → the whole text is the document.
        let text = "---\ntitle: x\nHola mundo"
        let skipped = TextMetrics.count(text, skippingFrontMatter: true)
        XCTAssertEqual(skipped, TextMetrics.count(text))
    }
}
