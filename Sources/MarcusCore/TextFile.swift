import Foundation

/// Line terminator style of a text file (ROADMAP D11: the file's line endings
/// are preserved). In memory Marcus works with `\n` only; the style detected
/// on read is restored on write, so a CRLF file stays CRLF after editing
/// instead of ending up mixed (Return inserts `\n`).
public enum LineEnding: Equatable, Sendable {
    case lf, crlf, cr

    public var string: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    /// The dominant terminator in `text`, or nil when it has none. Ties go
    /// to the more canonical style (LF over CRLF over CR).
    public static func detect(in text: String) -> LineEnding? {
        var lf = 0, crlf = 0, cr = 0
        let u = Array(text.utf16)
        var i = 0
        while i < u.count {
            if u[i] == 0x0D {
                if i + 1 < u.count, u[i + 1] == 0x0A { crlf += 1; i += 2; continue }
                cr += 1
            } else if u[i] == 0x0A {
                lf += 1
            }
            i += 1
        }
        guard lf + crlf + cr > 0 else { return nil }
        if lf >= crlf, lf >= cr { return .lf }
        if crlf >= cr { return .crlf }
        return .cr
    }

    /// `text` with every terminator (CRLF, lone CR, LF) as `\n`. Returns the
    /// input untouched — no copy — when it has no CR at all.
    public static func normalized(_ text: String) -> String {
        let ns = text as NSString
        guard ns.range(of: "\r").location != NSNotFound else { return text }
        return ns.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// `text` with every terminator in this style. Normalizes first, so a
    /// `\r\n` pasted into an LF buffer never becomes `\r\r\n`.
    public func restoring(_ text: String) -> String {
        let normalized = LineEnding.normalized(text)
        guard self != .lf else { return normalized }
        return (normalized as NSString).replacingOccurrences(of: "\n", with: string)
    }
}

/// Why a file could not be opened as text. Honest refusals: Marcus would
/// rather not open a file than autosave a damaged copy over the original.
public enum TextDecodingError: Error, Equatable, Sendable {
    /// Contains NUL bytes without a UTF-16/32 byte-order mark: binary data,
    /// not text (an image squeezed through Latin-1 would "decode" fine).
    case binary
    /// Only a lossy conversion could produce a string; characters would be
    /// replaced and written back as such on the first autosave.
    case lossy
    /// No encoding yields a string at all.
    case undecodable
}

/// Reading and writing the bytes of a text file (ROADMAP D11): UTF-8 first
/// (BOM tolerated), UTF-16/32 by BOM, then lossless encoding detection as a
/// fallback; output is always UTF-8 without BOM, in the file's own line
/// ending style. Pure Foundation, testable without AppKit.
public enum TextFile {

    public struct Decoded: Equatable, Sendable {
        public let text: String
        public let lineEnding: LineEnding

        public init(text: String, lineEnding: LineEnding) {
            self.text = text
            self.lineEnding = lineEnding
        }
    }

    /// The file's text with `\n` terminators, plus the style they had.
    public static func decode(_ data: Data) throws -> Decoded {
        let raw = try decodeString(data)
        let ending = LineEnding.detect(in: raw) ?? .lf
        return Decoded(text: LineEnding.normalized(raw), lineEnding: ending)
    }

    /// UTF-8 without BOM, with `text`'s terminators normalized to `lineEnding`.
    public static func encode(_ text: String, lineEnding: LineEnding) -> Data {
        Data(lineEnding.restoring(text).utf8)
    }

    private static func decodeString(_ data: Data) throws -> String {
        // Byte-order marks first: UTF-16/32 text legitimately contains NUL
        // bytes, so they must be recognized before the binary check.
        if let text = decodeByBOM(data) { return text }

        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        if let text = String(data: data, encoding: .utf8) { return text }

        if data.contains(0) { throw TextDecodingError.binary }

        var converted: NSString?
        var lossy: ObjCBool = false
        let encoding = NSString.stringEncoding(
            for: data,
            encodingOptions: [.allowLossyKey: false],
            convertedString: &converted,
            usedLossyConversion: &lossy
        )
        guard encoding != 0, let text = converted as String? else {
            throw TextDecodingError.undecodable
        }
        if lossy.boolValue { throw TextDecodingError.lossy }
        return text
    }

    private static func decodeByBOM(_ data: Data) -> String? {
        let utf32Encoding: String.Encoding
        if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            utf32Encoding = .utf32BigEndian
        } else if data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            utf32Encoding = .utf32LittleEndian
        } else if data.starts(with: [0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE]) {
            // .utf16 honors (and strips) the BOM itself.
            return String(data: data, encoding: .utf16)
        } else {
            return nil
        }
        return String(data: data.dropFirst(4), encoding: utf32Encoding)
    }
}
