import XCTest
@testable import MarcusCore

final class UniqueFileNameTests: XCTestCase {

    func testAddsTheMarkdownExtension() {
        XCTAssertEqual(UniqueFileName.markdownFileName(from: "Notes"), "Notes.md")
        XCTAssertEqual(UniqueFileName.markdownFileName(from: "Notes.md"), "Notes.md")
        XCTAssertEqual(UniqueFileName.markdownFileName(from: "Notes.markdown"), "Notes.markdown")
        // Not a Markdown extension: it is part of the name.
        XCTAssertEqual(UniqueFileName.markdownFileName(from: "v1.2"), "v1.2.md")
    }

    func testCleansWhatAFileNameCannotHold() {
        XCTAssertEqual(UniqueFileName.markdownFileName(from: "  a/b:c  "), "a-b-c.md")
        XCTAssertEqual(UniqueFileName.markdownFileName(from: ""), "Untitled.md")
        XCTAssertEqual(UniqueFileName.markdownFileName(from: "   "), "Untitled.md")
        XCTAssertEqual(UniqueFileName.markdownFileName(from: ".hidden"), "hidden.md")
    }

    func testNumbersATakenName() {
        let taken: Set<String> = ["Note.md", "Note 2.md"]
        XCTAssertEqual(UniqueFileName.available("Note.md", exists: taken.contains), "Note 3.md")
        XCTAssertEqual(UniqueFileName.available("Other.md", exists: taken.contains), "Other.md")
        XCTAssertEqual(UniqueFileName.available("README", exists: { $0 == "README" }), "README 2")
    }
}
