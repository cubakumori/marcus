import Foundation

/// Appending text to a document from outside (Shortcuts, AppleScript):
/// the file's own conventions survive — its line ending style is the
/// caller's business (`TextFile`), and whether it ended with a newline is
/// preserved here, so a file that ended cleanly still does and one that
/// did not is not forced to.
public enum TextAppend {

    /// `original` (with `\n` terminators) followed by `text`. With
    /// `onNewLine`, `text` starts on a line of its own: a terminator is
    /// added when the original does not already end with one. An empty
    /// original just takes the text. The result ends with a newline exactly
    /// when the original did (or was empty), whatever `text` ends with.
    public static func appended(_ text: String, to original: String, onNewLine: Bool) -> String {
        let normalizedText = LineEnding.normalized(text)
        guard !original.isEmpty else {
            return normalizedText.hasSuffix("\n") ? normalizedText : normalizedText + "\n"
        }
        let endedWithNewline = original.hasSuffix("\n")
        var result = original
        if onNewLine, !endedWithNewline {
            result += "\n"
        }
        result += normalizedText
        if endedWithNewline, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !endedWithNewline, result.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }
}
