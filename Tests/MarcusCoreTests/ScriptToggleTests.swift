import XCTest
@testable import MarcusCore

final class ScriptToggleTests: XCTestCase {

    // MARK: - Digits and signs (complete both ways)

    func testSuperscriptDigit() {
        XCTAssertEqual(ScriptToggle.superscripted("2"), "\u{00B2}")
    }

    func testSubscriptDigit() {
        XCTAssertEqual(ScriptToggle.subscripted("2"), "\u{2082}")
    }

    func testSuperscriptSigns() {
        XCTAssertEqual(ScriptToggle.superscripted("(-2)"), "\u{207D}\u{207B}\u{00B2}\u{207E}")
    }

    func testSubscriptSigns() {
        XCTAssertEqual(ScriptToggle.subscripted("(-2)"), "\u{208D}\u{208B}\u{2082}\u{208E}")
    }

    // MARK: - The marquee case: chemistry falls out of the honest limit

    func testSubscriptLeavesUppercaseChemistry() {
        // H and O have no subscript form, so only the 2 drops: H₂O.
        XCTAssertEqual(ScriptToggle.subscripted("H2O"), "H\u{2082}O")
    }

    func testSuperscriptConvertsAllAvailable() {
        // Superscript has uppercase H and O, so the whole thing converts.
        XCTAssertEqual(ScriptToggle.superscripted("H2O"), "\u{1D34}\u{00B2}\u{1D3C}")
    }

    // MARK: - Honest limit: non-convertible characters are left untouched

    func testUnconvertibleLetterUntouchedSubscript() {
        // q has no subscript form; nothing converts, nothing reverts.
        XCTAssertEqual(ScriptToggle.subscripted("q"), "q")
    }

    func testPartialLetterConversionSubscript() {
        // a→ₐ, b and c have no subscript form and stay.
        XCTAssertEqual(ScriptToggle.subscripted("abc"), "\u{2090}bc")
    }

    func testEmptyString() {
        XCTAssertEqual(ScriptToggle.superscripted(""), "")
        XCTAssertEqual(ScriptToggle.subscripted(""), "")
    }

    // MARK: - Toggle (revert)

    func testSuperscriptTogglesBack() {
        XCTAssertEqual(ScriptToggle.superscripted(ScriptToggle.superscripted("2")), "2")
    }

    func testSubscriptTogglesBackChemistry() {
        XCTAssertEqual(ScriptToggle.subscripted(ScriptToggle.subscripted("H2O")), "H2O")
    }

    func testRevertOnlyWhenNothingLeftToConvert() {
        // "x2": x→ₓ and 2→₂ both convert first.
        XCTAssertEqual(ScriptToggle.subscripted("x2"), "\u{2093}\u{2082}")
        // Now fully subscript: reverts to ASCII.
        XCTAssertEqual(ScriptToggle.subscripted("\u{2093}\u{2082}"), "x2")
    }

    func testMixedConvertedAndPlainConvertsTheRest() {
        // "x²2" has a superscript ² already plus plain x and 2 → still converts.
        let once = ScriptToggle.superscripted("x\u{00B2}2")
        XCTAssertEqual(once, "\u{02E3}\u{00B2}\u{00B2}")
        // A second pass (all superscript now) reverts, normalising to ASCII.
        XCTAssertEqual(ScriptToggle.superscripted(once), "x22")
    }

    func testSubscriptDoesNotDisturbSuperscript() {
        // Applying subscript to a superscript ² leaves it: nothing sub-convertible
        // except x, so x→ₓ and ² stays.
        XCTAssertEqual(ScriptToggle.subscripted("x\u{00B2}"), "\u{2093}\u{00B2}")
    }

    // MARK: - Every map entry round-trips (guards the escaped code points)

    func testSuperscriptMapRoundTripsEveryEntry() {
        for (ascii, form) in ScriptToggle.superscriptMap {
            XCTAssertEqual(ScriptToggle.superscripted(String(ascii)), String(form),
                           "forward \(ascii)")
            XCTAssertEqual(ScriptToggle.superscripted(String(form)), String(ascii),
                           "revert \(form)")
        }
    }

    func testSubscriptMapRoundTripsEveryEntry() {
        for (ascii, form) in ScriptToggle.subscriptMap {
            XCTAssertEqual(ScriptToggle.subscripted(String(ascii)), String(form),
                           "forward \(ascii)")
            XCTAssertEqual(ScriptToggle.subscripted(String(form)), String(ascii),
                           "revert \(form)")
        }
    }

    func testNoFormShared() {
        // A super and a sub form must never collide (disjoint sets), or the
        // inverse maps would be ambiguous.
        let superForms = Set(ScriptToggle.superscriptMap.values)
        let subForms = Set(ScriptToggle.subscriptMap.values)
        XCTAssertTrue(superForms.isDisjoint(with: subForms))
    }
}
