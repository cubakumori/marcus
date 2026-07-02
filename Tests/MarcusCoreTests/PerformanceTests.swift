import XCTest
@testable import MarcusCore

/// Guards the ROADMAP performance budgets at the scanner level:
/// opening a file requires a full scan; every keystroke currently requires
/// a re-scan. Budgets here are stricter than the user-facing ones because
/// attribute application and layout also spend from the same budget.
final class PerformanceTests: XCTestCase {

    /// Budgets are asserted against optimized code: `swift test -c release`.
    override func setUpWithError() throws {
        #if DEBUG
        throw XCTSkip("performance budgets are only meaningful in release builds (swift test -c release)")
        #endif
    }

    /// Realistic Markdown mix, ~1 KB per repetition.
    private static func syntheticDocument(bytes: Int) -> String {
        let block = """
        # Section title

        A paragraph with **bold text**, *emphasis*, `inline code` and a \
        [link](https://example.com/some/path) to somewhere else entirely.

        - first item with `code`
        - second item with **bold**
        1. ordered item
        2. another one

        > A blockquote line with *emphasis* running through it.

        ```swift
        let value = compute(from: input)
        return value.map { $0 * 2 }
        ```

        Another paragraph to round out the block with plain text only.

        ---

        """
        var result = ""
        result.reserveCapacity(bytes + block.count)
        while result.utf8.count < bytes { result += block }
        return result
    }

    private func measureMedian(runs: Int = 5, _ body: () -> Void) -> TimeInterval {
        var times: [TimeInterval] = []
        for _ in 0..<runs {
            let start = ContinuousClock.now
            body()
            times.append(Double((ContinuousClock.now - start).components.attoseconds) / 1e18)
        }
        return times.sorted()[times.count / 2]
    }

    func testScan1MBWithinOpenBudget() {
        let text = Self.syntheticDocument(bytes: 1_000_000)
        let median = measureMedian { _ = MarkdownScanner.scan(text) }
        print("PERF scan 1MB: \(Int(median * 1000)) ms")
        // Open budget for 1 MB is 100 ms total; the scan may use half.
        XCTAssertLessThan(median, 0.05, "scanning 1 MB blew the open budget")
    }

    func testScan10MBWithinOpenBudget() {
        let text = Self.syntheticDocument(bytes: 10_000_000)
        let median = measureMedian { _ = MarkdownScanner.scan(text) }
        print("PERF scan 10MB: \(Int(median * 1000)) ms")
        // Open budget for 10 MB is 1 s total; the scan may use half.
        XCTAssertLessThan(median, 0.5, "scanning 10 MB blew the open budget")
    }

    func testKeystrokeRescan10MBWithinTypingBudget() {
        // A keystroke re-scans incrementally from the edited line. The typing
        // budget is 16 ms per keystroke including attribute application and
        // layout, so the scan itself must stay well under it even at 10 MB.
        let original = Self.syntheticDocument(bytes: 10_000_000)
        let scan = MarkdownScanner.scan(original)
        // Worst-ish case: edit near the start so the tail splice is maximal.
        var edited = original
        edited.insert("x", at: edited.index(edited.startIndex, offsetBy: 5000))
        let editedRange = NSRange(location: 5000, length: 1)

        let median = measureMedian {
            _ = MarkdownScanner.rescan(after: scan, editedRange: editedRange, delta: 1, in: edited)
        }
        print("PERF keystroke incremental rescan 10MB: \(String(format: "%.2f", median * 1000)) ms")
        XCTAssertLessThan(median, 0.008, "keystroke re-scan blew the typing budget")
    }
}
