import Foundation

/// Word and character counts for the counter bar. Pure and thread-safe:
/// the editor runs it off the main thread on a copy of the text.
public enum TextMetrics {

    public struct Counts: Equatable, Sendable {
        public let words: Int
        public let characters: Int

        public init(words: Int, characters: Int) {
            self.words = words
            self.characters = characters
        }
    }

    public static func count(_ text: String) -> Counts {
        var words = 0
        // Linguistic word enumeration: skips punctuation-only tokens, so
        // Markdown markers (#, -, *) don't inflate the count.
        text.enumerateSubstrings(
            in: text.startIndex..., options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in words += 1 }
        return Counts(words: words, characters: text.count)
    }
}
