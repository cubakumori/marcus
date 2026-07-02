import XCTest
@testable import MarcusCore

/// Deterministic PRNG so failures are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class IncrementalRescanTests: XCTestCase {

    /// Nasty fragments that flip scanner state when inserted or deleted.
    private static let fragments = [
        "\n", "\r\n", "```", "```swift\n", "~~~", "# ", "## title\n", "**",
        "*", "`", "---\n", "- - -", "> ", "- ", "1. ", "12) ", "[x](y)",
        "]", "(", "    ", "\t", "plain words here", "***", "__", "x",
    ]

    private static let baseDocument = """
    # Título

    Un párrafo con **negrita**, *cursiva*, `código` y un [enlace](https://e.com).

    ```swift
    let x = 1
    ```

    - lista uno
    - lista dos

    > una cita

    1. ordenada
    2. otra

    ---

    Párrafo final con texto plano y algo más de contenido para editar.
    """

    private func assertEqualScans(_ a: MarkdownScan, _ b: MarkdownScan, context: String) {
        XCTAssertEqual(a.buffer, b.buffer, "buffer mismatch — \(context)")
        XCTAssertEqual(a.lines, b.lines, "lines mismatch — \(context)")
        XCTAssertEqual(a.entryStates, b.entryStates, "entry states mismatch — \(context)")
    }

    private func assertInvariants(_ scan: MarkdownScan, textLength: Int, context: String) {
        XCTAssertFalse(scan.lines.isEmpty, context)
        XCTAssertEqual(scan.lines.count, scan.entryStates.count, context)
        var previousStart = -1
        for line in scan.lines {
            XCTAssertGreaterThan(line.range.location, previousStart, "line starts not increasing — \(context)")
            XCTAssertLessThanOrEqual(NSMaxRange(line.range), textLength, "line out of bounds — \(context)")
            for span in line.spans {
                XCTAssertGreaterThanOrEqual(span.range.location, 0, context)
                XCTAssertLessThanOrEqual(NSMaxRange(span.range), line.range.length, "span out of line — \(context)")
            }
            previousStart = line.range.location
        }
    }

    /// 400 random edits; after each one the incremental re-scan must be
    /// indistinguishable from a full scan of the resulting text.
    func testRandomEditsMatchFullScan() {
        var rng = SplitMix64(state: 0xC0FFEE)
        let text = NSMutableString(string: Self.baseDocument)
        var scan = MarkdownScanner.scan(text as String)

        for step in 0..<400 {
            let insert = Bool.random(using: &rng)
            let location = Int.random(in: 0...text.length, using: &rng)
            var editedRange: NSRange
            var delta: Int
            if insert || text.length == 0 {
                let fragment = Self.fragments.randomElement(using: &rng)!
                let fragmentLength = (fragment as NSString).length
                text.insert(fragment, at: location)
                editedRange = NSRange(location: location, length: fragmentLength)
                delta = fragmentLength
            } else {
                let maxLen = min(text.length - location, 12)
                let length = maxLen == 0 ? 0 : Int.random(in: 0...maxLen, using: &rng)
                text.deleteCharacters(in: NSRange(location: location, length: length))
                editedRange = NSRange(location: location, length: 0)
                delta = -length
            }

            let context = "step \(step), edit \(editedRange), delta \(delta)"
            let (incremental, dirty) = MarkdownScanner.rescan(after: scan, editedRange: editedRange, delta: delta, in: text as String)
            let full = MarkdownScanner.scan(text as String)
            assertEqualScans(incremental, full, context: context)
            assertInvariants(incremental, textLength: text.length, context: context)
            XCTAssertTrue(dirty.lowerBound >= 0 && dirty.upperBound <= incremental.lines.count, context)
            scan = incremental
        }
    }

    /// The dirty range must cover every line whose rendering changed:
    /// re-styling only the dirty lines of the old attribute state must yield
    /// the same per-line styling a full scan would produce.
    func testDirtyLinesCoverAllRenderingChanges() {
        var rng = SplitMix64(state: 0xBADA55)
        let text = NSMutableString(string: Self.baseDocument)
        var scan = MarkdownScanner.scan(text as String)
        // Simulated attribute state: what's "on screen" per line, keyed by line start.
        var styled: [Int: ScannedLine] = Dictionary(uniqueKeysWithValues: scan.lines.map { ($0.range.location, $0) })

        for step in 0..<200 {
            let location = Int.random(in: 0...text.length, using: &rng)
            let fragment = Self.fragments.randomElement(using: &rng)!
            let fragmentLength = (fragment as NSString).length
            text.insert(fragment, at: location)
            let editedRange = NSRange(location: location, length: fragmentLength)

            let (incremental, dirty) = MarkdownScanner.rescan(after: scan, editedRange: editedRange, delta: fragmentLength, in: text as String)

            // Shift the on-screen state the way NSTextStorage shifts attributes.
            var shifted: [Int: ScannedLine] = [:]
            for (start, line) in styled {
                if start < location || (start == location && fragmentLength == 0) {
                    shifted[start] = line
                } else if start >= location {
                    shifted[start + fragmentLength] = ScannedLine(
                        range: NSRange(location: line.range.location + fragmentLength, length: line.range.length),
                        kind: line.kind,
                        spans: line.spans
                    )
                }
            }
            for index in dirty { shifted[incremental.lines[index].range.location] = incremental.lines[index] }

            for line in incremental.lines {
                guard let onScreen = shifted[line.range.location], onScreen.contentEquals(line) else {
                    // A changed line not covered by the dirty range would
                    // leave stale styling on screen.
                    XCTAssertTrue(dirty.contains(where: { incremental.lines[$0].range.location == line.range.location }),
                                  "step \(step): line at \(line.range.location) changed but was not dirty")
                    continue
                }
            }
            styled = Dictionary(uniqueKeysWithValues: incremental.lines.map { ($0.range.location, $0) })
            scan = incremental
        }
    }

    /// Robustness torture: scan a pathological document and check invariants.
    func testTortureDocumentInvariants() {
        var rng = SplitMix64(state: 0xDEAD10CC)
        var torture = ""
        for _ in 0..<5000 { torture += Self.fragments.randomElement(using: &rng)! }
        let scan = MarkdownScanner.scan(torture)
        assertInvariants(scan, textLength: (torture as NSString).length, context: "torture")
    }
}
