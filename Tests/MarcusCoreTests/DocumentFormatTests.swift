import XCTest
@testable import MarcusCore

final class DocumentFormatTests: XCTestCase {

    // MARK: - Markdown

    func testMarkdownExtensions() {
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "md"), .markdown)
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "markdown"), .markdown)
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "mdown"), .markdown)
    }

    func testUntitledDocumentIsMarkdown() {
        // No file yet (nil, not empty): new documents are Markdown.
        XCTAssertEqual(DocumentFormat.classify(pathExtension: nil), .markdown)
    }

    // MARK: - Plain text

    func testPlainTextExtensions() {
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "txt"), .plainText)
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "text"), .plainText)
    }

    // MARK: - Everything else, by extension only

    func testOtherFormatsKeepTheirExtension() {
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "html"),
                       .other(fileExtension: "html"))
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "conf"),
                       .other(fileExtension: "conf"))
    }

    func testFileWithoutExtensionIsOther() {
        // A saved file with no extension (Makefile, LICENSE) is not a new
        // document: URL.pathExtension gives "", and "" is not Markdown.
        XCTAssertEqual(DocumentFormat.classify(pathExtension: ""),
                       .other(fileExtension: ""))
    }

    func testClassificationIsCaseInsensitive() {
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "MD"), .markdown)
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "TXT"), .plainText)
        XCTAssertEqual(DocumentFormat.classify(pathExtension: "Html"),
                       .other(fileExtension: "html"))
    }

    // MARK: - Capabilities

    func testMarkdownTreatmentCoversMarkdownAndPlainText() {
        // Fase 6 scope note: .txt keeps the full Fase 4 treatment
        // (highlighting, preview, export); only the new formats are
        // edited as honest plain text.
        XCTAssertTrue(DocumentFormat.markdown.supportsMarkdown)
        XCTAssertTrue(DocumentFormat.plainText.supportsMarkdown)
        XCTAssertFalse(DocumentFormat.other(fileExtension: "html").supportsMarkdown)
    }

    func testOnlyMarkdownIsMarkdown() {
        // The window subtitle appears for every non-Markdown document,
        // .txt included: it *is* plain text and says so.
        XCTAssertTrue(DocumentFormat.markdown.isMarkdown)
        XCTAssertFalse(DocumentFormat.plainText.isMarkdown)
        XCTAssertFalse(DocumentFormat.other(fileExtension: "log").isMarkdown)
    }
}
