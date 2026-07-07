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

    /// - Parameter skippingFrontMatter: when true, a leading YAML front
    ///   matter block (Fase 7, D16) is dropped before counting — it is
    ///   metadata, not the document, just as the preview and exports treat
    ///   it. Callers pass true only where Markdown treatment applies.
    public static func count(_ text: String, skippingFrontMatter: Bool = false) -> Counts {
        var text = text
        if skippingFrontMatter, let block = FrontMatter.block(in: text) {
            text = (text as NSString).substring(from: block.utf16Length)
        }
        var words = 0
        // Linguistic word enumeration: skips punctuation-only tokens, so
        // Markdown markers (#, -, *) don't inflate the count.
        text.enumerateSubstrings(
            in: text.startIndex..., options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in words += 1 }
        return Counts(words: words, characters: text.count)
    }
}
