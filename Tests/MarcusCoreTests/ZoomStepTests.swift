import XCTest
@testable import MarcusCore

final class ZoomStepTests: XCTestCase {

    func testZoomInFromNormal() {
        XCTAssertEqual(ZoomStep.zoomedIn(1.0), 1.1, accuracy: 1e-9)
    }

    func testZoomOutFromNormal() {
        XCTAssertEqual(ZoomStep.zoomedOut(1.0), 0.9, accuracy: 1e-9)
    }

    func testInThenOutReturnsExactly() {
        // The 0.1 grid must not drift over a round trip.
        XCTAssertEqual(ZoomStep.zoomedOut(ZoomStep.zoomedIn(1.0)), 1.0, accuracy: 1e-9)
    }

    func testClampsAtMaximum() {
        var f = 1.0
        for _ in 0..<100 { f = ZoomStep.zoomedIn(f) }
        XCTAssertEqual(f, ZoomStep.maximum, accuracy: 1e-9)
    }

    func testClampsAtMinimum() {
        var f = 1.0
        for _ in 0..<100 { f = ZoomStep.zoomedOut(f) }
        XCTAssertEqual(f, ZoomStep.minimum, accuracy: 1e-9)
    }

    func testClampBounds() {
        XCTAssertEqual(ZoomStep.clamp(0.0), ZoomStep.minimum, accuracy: 1e-9)
        XCTAssertEqual(ZoomStep.clamp(9.9), ZoomStep.maximum, accuracy: 1e-9)
        XCTAssertEqual(ZoomStep.clamp(1.5), 1.5, accuracy: 1e-9)
    }

    func testClampSnapsToGrid() {
        // A drifted value snaps back to the 0.1 grid.
        XCTAssertEqual(ZoomStep.clamp(1.2000000001), 1.2, accuracy: 1e-9)
    }

    func testFullRangeRoundTrip() {
        // Up to the cap and back down lands exactly on normal-adjacent grid.
        var f = ZoomStep.minimum
        for _ in 0..<100 { f = ZoomStep.zoomedIn(f) }
        XCTAssertEqual(f, ZoomStep.maximum, accuracy: 1e-9)
        for _ in 0..<100 { f = ZoomStep.zoomedOut(f) }
        XCTAssertEqual(f, ZoomStep.minimum, accuracy: 1e-9)
    }
}
