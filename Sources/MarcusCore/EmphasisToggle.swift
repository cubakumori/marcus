import Foundation

/// Wraps or unwraps a selection in emphasis delimiters (⌘B / ⌘I writing
/// aid). Star-count arithmetic keeps bold and italic composable:
/// `*` (italic) toggles one star, `**` (bold) toggles two.
public enum EmphasisToggle {

    public static func toggled(_ text: String, delimiter: String) -> String {
        let width = delimiter.count  // 1 (italic) or 2 (bold)
        let leading = text.prefix(while: { $0 == "*" }).count
        let trailing = text.reversed().prefix(while: { $0 == "*" }).count
        // Star run cleanly wrapping the selection on both sides (cap 3:
        // beyond bold+italic it is content, not markup).
        let run = min(leading, trailing, 3)
        let isWrapped = run > 0 && text.count > 2 * run

        let unwraps = isWrapped && (width == 1 ? run % 2 == 1 : run >= 2)
        if unwraps {
            return String(text.dropFirst(width).dropLast(width))
        }
        return delimiter + text + delimiter
    }
}
