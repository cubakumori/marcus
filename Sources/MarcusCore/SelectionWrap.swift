import Foundation

/// Typing a Markdown delimiter over a selection wraps it instead of
/// replacing it (writing aid, a setting): `*` → `*text*`, `[` → `[text]`.
/// Pure text logic; the editor decides when it applies (setting on,
/// Markdown document, editable) and performs the edit.
public enum SelectionWrap {

    /// The delimiters that wrap, and what closes each (only `[` differs).
    public static let closers: [Character: Character] = ["*": "*", "_": "_", "`": "`", "~": "~", "[": "]"]

    public struct Result: Equatable, Sendable {
        /// What replaces the selected text.
        public let replacement: String
        /// The wrapped text inside the delimiters, relative to the start of
        /// the replacement — the selection stays there, so typing the same
        /// key again nests (`**text**`, `~~text~~`).
        public let inner: NSRange
    }

    /// Nil when the keystroke should be typed as usual: not a lone
    /// delimiter, nothing selected, a multi-line selection, or only
    /// whitespace selected. Whitespace at the edges of the selection stays
    /// outside the delimiters (`* text *` is not emphasis; ` *text* ` is).
    public static func wrap(_ selected: String, typing typed: String) -> Result? {
        guard typed.count == 1, let open = typed.first, let close = closers[open] else { return nil }
        // `isNewline` also catches "\r\n", which Swift treats as one Character.
        guard !selected.isEmpty, !selected.contains(where: \.isNewline) else { return nil }
        let leading = selected.prefix(while: { $0.isWhitespace })
        let trailing = selected.reversed().prefix(while: { $0.isWhitespace }).reversed()
        let core = selected.dropFirst(leading.count).dropLast(trailing.count)
        guard !core.isEmpty else { return nil }
        let replacement = String(leading) + String(open) + core + String(close) + String(trailing)
        let inner = NSRange(location: String(leading).utf16.count + 1, length: String(core).utf16.count)
        return Result(replacement: replacement, inner: inner)
    }
}
