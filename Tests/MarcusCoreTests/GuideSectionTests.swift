import XCTest
@testable import MarcusCore

final class GuideSectionTests: XCTestCase {

    func testFindsTheHeadingLineInEitherLanguage() {
        let es = "# Guía\n\nIntro\n\n## Markdown, con ejemplos\n\n### Tablas\n\n| a |\n"
        let en = "# Guide\n\n## Markdown, exemplified\n\n### Tables\n"
        // The whole heading line, markers included (the navigation target).
        XCTAssertEqual(GuideSection.markdown.range(in: es), (es as NSString).range(of: "## Markdown, con ejemplos"))
        XCTAssertEqual(GuideSection.tables.range(in: es), (es as NSString).range(of: "### Tablas"))
        XCTAssertEqual(GuideSection.markdown.range(in: en), (en as NSString).range(of: "## Markdown, exemplified"))
        XCTAssertEqual(GuideSection.tables.range(in: en), (en as NSString).range(of: "### Tables"))
    }

    func testMissingHeadingGivesNil() {
        XCTAssertNil(GuideSection.images.range(in: "# Guía\n\nSin secciones\n"))
        // Only headings count: the title in running text or in a table does not.
        XCTAssertNil(GuideSection.tables.range(in: "Tablas\n\n| Tablas |\n|---|\n"))
    }

    /// Every section the Help menu offers exists exactly once in each
    /// shipped guide, so the menu never lands on the wrong place or
    /// nowhere. Reads the guides from the repository, as the app's bundle
    /// is not available to this target.
    func testEveryShippedGuideHasEverySectionOnce() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Marcus/Resources")
        for name in ["Guide.es.md", "Guide.en.md"] {
            let text = try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)
            let items = MarkdownOutline.items(from: MarkdownScanner.scan(text), in: text)
            for section in GuideSection.allCases {
                let matches = items.filter { section.headingTitles.contains($0.title) }
                XCTAssertEqual(matches.count, 1, "\(section) in \(name): \(matches.map(\.title))")
                XCTAssertNotNil(section.range(in: text), "\(section) in \(name)")
            }
        }
    }

    /// Both guides are the same manual: same heading skeleton (levels in
    /// order), so a section added to one is not forgotten in the other.
    func testBothGuidesShareTheHeadingSkeleton() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Marcus/Resources")
        func levels(_ name: String) throws -> [Int] {
            let text = try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)
            return MarkdownOutline.items(from: MarkdownScanner.scan(text), in: text).map(\.level)
        }
        XCTAssertEqual(try levels("Guide.es.md"), try levels("Guide.en.md"))
    }
}
