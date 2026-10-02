import XCTest
@testable import MarcusCore

final class TextFileTests: XCTestCase {

    // MARK: - Line ending detection

    func testDetectsLF() {
        XCTAssertEqual(LineEnding.detect(in: "a\nb\nc"), .lf)
    }

    func testDetectsCRLF() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\r\nc"), .crlf)
    }

    func testDetectsLoneCR() {
        XCTAssertEqual(LineEnding.detect(in: "a\rb\rc"), .cr)
    }

    func testDetectsNothingWithoutTerminators() {
        XCTAssertNil(LineEnding.detect(in: "single line"))
        XCTAssertNil(LineEnding.detect(in: ""))
    }

    func testDominantStyleWinsInMixedText() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\r\nc\nd"), .crlf)
        XCTAssertEqual(LineEnding.detect(in: "a\nb\nc\r\nd"), .lf)
    }

    func testTiesPreferTheCanonicalStyle() {
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\nc"), .lf)
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb\rc"), .crlf)
    }

    func testCRLFCountsOnceNotAsCRPlusLF() {
        // One CRLF must not register as a CR and an LF vote.
        XCTAssertEqual(LineEnding.detect(in: "a\r\nb"), .crlf)
    }

    // MARK: - Normalization

    func testNormalizesCRLFAndCR() {
        XCTAssertEqual(LineEnding.normalized("a\r\nb\rc\nd"), "a\nb\nc\nd")
    }

    func testNormalizedLeavesLFTextUntouched() {
        let text = "a\nb\n"
        XCTAssertEqual(LineEnding.normalized(text), text)
    }

    func testRestoringRewritesEveryTerminator() {
        XCTAssertEqual(LineEnding.crlf.restoring("a\nb\n"), "a\r\nb\r\n")
        XCTAssertEqual(LineEnding.cr.restoring("a\nb"), "a\rb")
        XCTAssertEqual(LineEnding.lf.restoring("a\nb"), "a\nb")
    }

    func testRestoringNormalizesPastedCRLFFirst() {
        // A \r\n pasted into the LF buffer must not become \r\r\n.
        XCTAssertEqual(LineEnding.crlf.restoring("a\r\nb\nc"), "a\r\nb\r\nc")
        XCTAssertEqual(LineEnding.lf.restoring("a\r\nb"), "a\nb")
    }

    // MARK: - Decoding

    func testDecodesUTF8AndStripsBOM() throws {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("niño\n".utf8)
        let decoded = try TextFile.decode(Data(bytes))
        XCTAssertEqual(decoded.text, "niño\n")
        XCTAssertEqual(decoded.lineEnding, .lf)
    }

    func testDecodeNormalizesAndReportsCRLF() throws {
        let decoded = try TextFile.decode(Data("a\r\nb\r\n".utf8))
        XCTAssertEqual(decoded.text, "a\nb\n")
        XCTAssertEqual(decoded.lineEnding, .crlf)
    }

    func testDecodesLatin1Losslessly() throws {
        // "año" in ISO Latin 1: ñ is a single 0xF1 byte, invalid as UTF-8.
        let decoded = try TextFile.decode(Data([0x61, 0xF1, 0x6F]))
        XCTAssertEqual(decoded.text, "año")
    }

    func testDecodesUTF16WithBOM() throws {
        let data = "héllo\r\n".data(using: .utf16)!  // emits a BOM
        let decoded = try TextFile.decode(data)
        XCTAssertEqual(decoded.text, "héllo\n")
        XCTAssertEqual(decoded.lineEnding, .crlf)
    }

    func testRefusesBinaryData() {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]
        XCTAssertThrowsError(try TextFile.decode(Data(png))) { error in
            XCTAssertEqual(error as? TextDecodingError, .binary)
        }
    }

    func testEmptyFileIsEmptyText() throws {
        let decoded = try TextFile.decode(Data())
        XCTAssertEqual(decoded.text, "")
        XCTAssertEqual(decoded.lineEnding, .lf)
    }

    // MARK: - Round trips

    func testCRLFFileRoundTripsByteForByte() throws {
        let original = Data("# Title\r\n\r\nline one\r\nline two\r\n".utf8)
        let decoded = try TextFile.decode(original)
        XCTAssertEqual(TextFile.encode(decoded.text, lineEnding: decoded.lineEnding), original)
    }

    func testCRFileRoundTripsByteForByte() throws {
        let original = Data("one\rtwo\rthree".utf8)
        let decoded = try TextFile.decode(original)
        XCTAssertEqual(TextFile.encode(decoded.text, lineEnding: decoded.lineEnding), original)
    }

    func testEditedCRLFFileKeepsItsStyle() throws {
        let decoded = try TextFile.decode(Data("a\r\nb\r\n".utf8))
        let edited = decoded.text + "c\n"  // Return in the editor inserts \n
        XCTAssertEqual(TextFile.encode(edited, lineEnding: decoded.lineEnding), Data("a\r\nb\r\nc\r\n".utf8))
    }

    func testEncodeWritesUTF8WithoutBOM() {
        XCTAssertEqual(TextFile.encode("ñ", lineEnding: .lf), Data([0xC3, 0xB1]))
    }
}
