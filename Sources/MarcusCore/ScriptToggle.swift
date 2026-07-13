import Foundation

/// Converts a selection to Unicode super/subscript characters as a writing
/// aid (Format menu, sibling of ⌘B/⌘I — see D17). Unlike `EmphasisToggle`,
/// which wraps text in delimiters, this transliterates each character to its
/// Unicode super/subscript form (`2` → `²`, `2` → `₂`). The file stores plain
/// Unicode, so preview, exports and Copy as HTML need no special handling.
///
/// Honest limit: only characters that Unicode actually has a super/subscript
/// form for are converted — digits and the five signs `+ - = ( )` are
/// complete both ways; letters are partial (uppercase has almost no subscript
/// form, which is why subscripting `H2O` yields `H₂O`). Anything without a
/// form is left untouched.
///
/// Toggle: if every character that could take this form is *already* in it
/// (nothing left to convert), the selection is reverted to plain ASCII;
/// otherwise the convertible characters are converted. Reverting always
/// normalises to ASCII, so a partially-converted selection may take two
/// invocations to come back fully.
public enum ScriptToggle {

    public static func superscripted(_ text: String) -> String {
        transform(text, forward: superscriptMap, inverse: superscriptInverse)
    }

    public static func subscripted(_ text: String) -> String {
        transform(text, forward: subscriptMap, inverse: subscriptInverse)
    }

    private static func transform(_ text: String,
                                  forward: [Character: Character],
                                  inverse: [Character: Character]) -> String {
        let hasPlainConvertible = text.contains { forward[$0] != nil }
        let hasConverted = text.contains { inverse[$0] != nil }
        // Already fully in this form (nothing left to convert): revert to ASCII.
        if hasConverted && !hasPlainConvertible {
            return String(text.map { inverse[$0] ?? $0 })
        }
        // Otherwise convert every character that has a form; leave the rest.
        return String(text.map { forward[$0] ?? $0 })
    }

    // MARK: - Character maps

    // Scalars are written as escapes on purpose: the intended code point is
    // reviewable at a glance and does not depend on pasting the right glyph.
    // `superscriptMapRoundTripsEveryEntry` / the subscript twin guard them.

    static let superscriptMap: [Character: Character] = [
        "0": "\u{2070}", "1": "\u{00B9}", "2": "\u{00B2}", "3": "\u{00B3}", "4": "\u{2074}",
        "5": "\u{2075}", "6": "\u{2076}", "7": "\u{2077}", "8": "\u{2078}", "9": "\u{2079}",
        "+": "\u{207A}", "-": "\u{207B}", "=": "\u{207C}", "(": "\u{207D}", ")": "\u{207E}",
        "a": "\u{1D43}", "b": "\u{1D47}", "c": "\u{1D9C}", "d": "\u{1D48}", "e": "\u{1D49}",
        "f": "\u{1DA0}", "g": "\u{1D4D}", "h": "\u{02B0}", "i": "\u{2071}", "j": "\u{02B2}",
        "k": "\u{1D4F}", "l": "\u{02E1}", "m": "\u{1D50}", "n": "\u{207F}", "o": "\u{1D52}",
        "p": "\u{1D56}", "r": "\u{02B3}", "s": "\u{02E2}", "t": "\u{1D57}", "u": "\u{1D58}",
        "v": "\u{1D5B}", "w": "\u{02B7}", "x": "\u{02E3}", "y": "\u{02B8}", "z": "\u{1DBB}",
        // No superscript form: q.
        "A": "\u{1D2C}", "B": "\u{1D2E}", "D": "\u{1D30}", "E": "\u{1D31}", "G": "\u{1D33}",
        "H": "\u{1D34}", "I": "\u{1D35}", "J": "\u{1D36}", "K": "\u{1D37}", "L": "\u{1D38}",
        "M": "\u{1D39}", "N": "\u{1D3A}", "O": "\u{1D3C}", "P": "\u{1D3E}", "R": "\u{1D3F}",
        "T": "\u{1D40}", "U": "\u{1D41}", "V": "\u{2C7D}", "W": "\u{1D42}",
        // No superscript form: C, F, Q, S, X, Y, Z.
    ]

    static let subscriptMap: [Character: Character] = [
        "0": "\u{2080}", "1": "\u{2081}", "2": "\u{2082}", "3": "\u{2083}", "4": "\u{2084}",
        "5": "\u{2085}", "6": "\u{2086}", "7": "\u{2087}", "8": "\u{2088}", "9": "\u{2089}",
        "+": "\u{208A}", "-": "\u{208B}", "=": "\u{208C}", "(": "\u{208D}", ")": "\u{208E}",
        "a": "\u{2090}", "e": "\u{2091}", "h": "\u{2095}", "i": "\u{1D62}", "j": "\u{2C7C}",
        "k": "\u{2096}", "l": "\u{2097}", "m": "\u{2098}", "n": "\u{2099}", "o": "\u{2092}",
        "p": "\u{209A}", "r": "\u{1D63}", "s": "\u{209B}", "t": "\u{209C}", "u": "\u{1D64}",
        "v": "\u{1D65}", "x": "\u{2093}",
        // No subscript form: b, c, d, f, g, q, w, y, z, and every uppercase letter.
    ]

    static let superscriptInverse: [Character: Character] = invert(superscriptMap)
    static let subscriptInverse: [Character: Character] = invert(subscriptMap)

    private static func invert(_ map: [Character: Character]) -> [Character: Character] {
        var inverse = [Character: Character]()
        for (ascii, form) in map { inverse[form] = ascii }
        return inverse
    }
}
