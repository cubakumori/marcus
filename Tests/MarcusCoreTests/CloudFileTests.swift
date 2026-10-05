import XCTest
@testable import MarcusCore

final class CloudFileTests: XCTestCase {

    func testAnOrdinaryFileHasItsData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cloudfile-\(UUID().uuidString).md")
        try "# hola\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(CloudFile.isDataless(url))
    }

    func testAMissingFileIsNotDataless() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).md")
        XCTAssertFalse(CloudFile.isDataless(url))
    }
}
