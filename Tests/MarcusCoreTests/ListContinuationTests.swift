import XCTest
@testable import MarcusCore

final class ListContinuationTests: XCTestCase {

    private func action(_ line: String) -> ListContinuation.Action? {
        ListContinuation.actionForReturn(in: line)
    }

    // MARK: Bullets

    func testContinuesDashBullet() {
        XCTAssertEqual(action("- item"), .insert("- "))
    }

    func testContinuesStarAndPlusBullets() {
        XCTAssertEqual(action("* item"), .insert("* "))
        XCTAssertEqual(action("+ item"), .insert("+ "))
    }

    func testKeepsIndentation() {
        XCTAssertEqual(action("   - nested"), .insert("   - "))
        XCTAssertEqual(action("\t- tabbed"), .insert("\t- "))
    }

    // MARK: Ordered

    func testIncrementsOrderedNumber() {
        XCTAssertEqual(action("3. three"), .insert("4. "))
    }

    func testOrderedWithParenDelimiter() {
        XCTAssertEqual(action("1) one"), .insert("2) "))
    }

    func testOrderedKeepsIndentation() {
        XCTAssertEqual(action("  7. seven"), .insert("  8. "))
    }

    // MARK: Task lists

    func testContinuesTaskListUnchecked() {
        XCTAssertEqual(action("- [ ] todo"), .insert("- [ ] "))
    }

    func testCheckedTaskContinuesUnchecked() {
        XCTAssertEqual(action("- [x] done"), .insert("- [ ] "))
    }

    // MARK: Ending a list

    func testEmptyBulletItemEndsList() {
        // Return on an empty item removes the marker (range is line-relative).
        XCTAssertEqual(action("- "), .endList(NSRange(location: 0, length: 2)))
    }

    func testEmptyIndentedOrderedItemEndsList() {
        XCTAssertEqual(action("  4. "), .endList(NSRange(location: 0, length: 5)))
    }

    func testEmptyTaskItemEndsList() {
        XCTAssertEqual(action("- [ ] "), .endList(NSRange(location: 0, length: 6)))
    }

    // MARK: Not lists

    func testPlainParagraphDoesNothing() {
        XCTAssertNil(action("just text"))
        XCTAssertNil(action(""))
    }

    func testDashWithoutSpaceIsNotAList() {
        XCTAssertNil(action("-nospace"))
    }

    func testThematicBreakIsNotAList() {
        XCTAssertNil(action("---"))
    }

    func testTrailingNewlineInLineIsTolerated() {
        XCTAssertEqual(action("- item\n"), .insert("- "))
    }
}
