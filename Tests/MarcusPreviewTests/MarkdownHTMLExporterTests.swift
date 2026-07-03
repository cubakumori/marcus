import XCTest
@testable import MarcusPreview

final class MarkdownHTMLExporterTests: XCTestCase {

    private func body(_ markdown: String, baseURL: URL? = nil) -> String {
        MarkdownHTMLExporter.body(from: markdown, options: .init(baseURL: baseURL))
    }

    // MARK: Blocks

    func testHeadingAndParagraph() {
        let html = body("# Title\n\nBody text.")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<p>Body text.</p>"))
    }

    func testTextIsEscaped() {
        let html = body("a < b & c > d")
        XCTAssertTrue(html.contains("a &lt; b &amp; c &gt; d"))
    }

    func testFencedCodeBlockKeepsLanguageAndEscapes() {
        let html = body("```swift\nlet x = a < b && c\n```")
        XCTAssertTrue(html.contains(#"<pre><code class="language-swift">"#))
        XCTAssertTrue(html.contains("let x = a &lt; b &amp;&amp; c"))
        XCTAssertTrue(html.contains("</code></pre>"))
    }

    func testCodeBlockWithoutLanguageHasNoClass() {
        let html = body("    indented code")
        XCTAssertTrue(html.contains("<pre><code>indented code"))
    }

    func testBlockquote() {
        let html = body("> quoted words")
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("quoted words"))
        XCTAssertTrue(html.contains("</blockquote>"))
    }

    func testThematicBreak() {
        XCTAssertTrue(body("---").contains("<hr>"))
    }

    func testUnorderedList() {
        let html = body("- one\n- two")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<li>one</li>"))
        XCTAssertTrue(html.contains("<li>two</li>"))
        XCTAssertTrue(html.contains("</ul>"))
    }

    func testOrderedListPreservesStart() {
        let html = body("3. three\n4. four")
        XCTAssertTrue(html.contains(#"<ol start="3">"#))
        XCTAssertTrue(html.contains("<li>three</li>"))
    }

    func testOrderedListFromOneHasNoStartAttribute() {
        let html = body("1. one")
        XCTAssertTrue(html.contains("<ol>"))
        XCTAssertFalse(html.contains("start="))
    }

    func testTaskListRendersDisabledCheckboxes() {
        let html = body("- [x] done\n- [ ] pending")
        XCTAssertTrue(html.contains(#"<input type="checkbox" checked disabled>"#))
        XCTAssertTrue(html.contains(#"<input type="checkbox" disabled>"#))
    }

    func testMultiParagraphListItemKeepsParagraphs() {
        let html = body("- first\n\n  second paragraph of the same item")
        XCTAssertTrue(html.contains("<p>first</p>"))
        XCTAssertTrue(html.contains("<p>second paragraph of the same item</p>"))
    }

    func testTableWithAlignment() {
        let html = body("""
        | Name | Price |
        |:-----|------:|
        | Tea  | 3     |
        """)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains(#"<th style="text-align: left">Name</th>"#))
        XCTAssertTrue(html.contains(#"<th style="text-align: right">Price</th>"#))
        XCTAssertTrue(html.contains(#"<td style="text-align: left">Tea</td>"#))
        XCTAssertTrue(html.contains("</tbody></table>"))
    }

    func testRawHTMLBlockPassesThrough() {
        let html = body("<div class=\"note\">kept</div>")
        XCTAssertTrue(html.contains("<div class=\"note\">kept</div>"))
    }

    // MARK: Inlines

    func testEmphasisStrongStrikethrough() {
        let html = body("*em* **strong** ~~gone~~")
        XCTAssertTrue(html.contains("<em>em</em>"))
        XCTAssertTrue(html.contains("<strong>strong</strong>"))
        XCTAssertTrue(html.contains("<del>gone</del>"))
    }

    func testInlineCodeEscapes() {
        let html = body("run `a < b`")
        XCTAssertTrue(html.contains("<code>a &lt; b</code>"))
    }

    func testLinkEscapesAttribute() {
        let html = body("[docs](https://example.com/?a=1&b=2)")
        XCTAssertTrue(html.contains(#"<a href="https://example.com/?a=1&amp;b=2">docs</a>"#))
    }

    func testHardLineBreak() {
        let html = body("line one  \nline two")
        XCTAssertTrue(html.contains("<br>"))
    }

    // MARK: Images

    func testLocalImageBecomesDataURI() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try bytes.write(to: dir.appendingPathComponent("pic.png"))

        let html = body("![alt text](pic.png)", baseURL: dir)
        XCTAssertTrue(html.contains(#"src="data:image/png;base64,\#(bytes.base64EncodedString())""#))
        XCTAssertTrue(html.contains(#"alt="alt text""#))
    }

    func testMissingLocalImageKeepsOriginalSource() {
        let html = body("![x](missing.png)", baseURL: URL(fileURLWithPath: "/nonexistent-dir"))
        XCTAssertTrue(html.contains(#"src="missing.png""#))
    }

    func testRemoteImageKeepsOriginalSource() {
        let html = body("![x](https://example.com/pic.png)")
        XCTAssertTrue(html.contains(#"src="https://example.com/pic.png""#))
    }

    // MARK: Document template

    func testDocumentIsSelfContainedWithEscapedTitle() {
        let html = MarkdownHTMLExporter.document(
            from: "# Hi", options: .init(title: "Notes <& drafts>"))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains(#"<meta charset="utf-8">"#))
        XCTAssertTrue(html.contains("<title>Notes &lt;&amp; drafts&gt;</title>"))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(html.contains("@media print"))
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertTrue(html.contains("</html>"))
        // Self-contained: no external fetches.
        XCTAssertFalse(html.contains("http://"))
        XCTAssertFalse(html.lowercased().contains("<script"))
    }
}
