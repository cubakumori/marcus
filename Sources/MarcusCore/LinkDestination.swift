import Foundation

/// Resolves a Markdown link or image destination to a URL the way
/// renderers do. `URL(string:)` alone fails on a common mix: raw non-ASCII
/// plus percent escapes (`año/mi%20foto.png`, as `ImageLink` writes and
/// people type) — Foundation then re-encodes the `%` and looks for a file
/// literally named `mi%20foto.png`. Encoding only the non-ASCII and the
/// whitespace first, and never an existing `%`, gives it a valid string.
public enum LinkDestination {

    public static func url(_ destination: String, relativeTo base: URL?) -> URL? {
        var ascii = ""
        for scalar in destination.unicodeScalars {
            if scalar.isASCII && !scalar.properties.isWhitespace {
                ascii.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { ascii += String(format: "%%%02X", byte) }
            }
        }
        return URL(string: ascii, relativeTo: base)
    }
}
