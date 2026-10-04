import XCTest
@testable import MarcusCore

final class ProjectLinksTests: XCTestCase {

    func testReleaseNotesPointAtTheVersionTag() {
        XCTAssertEqual(ProjectLinks.releaseNotesURL(version: "0.11.0").absoluteString,
                       "https://github.com/cubakumori/marcus/releases/tag/v0.11.0")
        // Already tagged, or with stray whitespace from a plist: same answer.
        XCTAssertEqual(ProjectLinks.releaseNotesURL(version: "v0.11.0"),
                       ProjectLinks.releaseNotesURL(version: " 0.11.0\n"))
    }

    func testIssueAndRepositoryLinks() {
        XCTAssertEqual(ProjectLinks.newIssueURL.absoluteString, "https://github.com/cubakumori/marcus/issues/new")
        XCTAssertEqual(ProjectLinks.repository.host, "github.com")
    }
}
