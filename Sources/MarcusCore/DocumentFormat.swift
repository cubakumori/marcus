/// Fase 6 (ROADMAP D15) — what kind of text a document holds, derived from
/// the file extension alone: the type follows the file, never the content.
public enum DocumentFormat: Equatable, Sendable {
    /// Markdown (`md`, `markdown`, `mdown`) — and every new document that
    /// has no file yet.
    case markdown
    /// Exact plain text (`txt`, `text`): Markdown's sibling format, keeps
    /// the full Markdown treatment from Fase 4.
    case plainText
    /// Anything else opened as text (HTML, CSS, logs, config files…).
    /// The extension is stored lowercased; it may be empty (Makefile).
    case other(fileExtension: String)

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
    private static let plainTextExtensions: Set<String> = ["txt", "text"]

    /// `nil` means "no file yet" (untitled document) and classifies as
    /// Markdown; an empty string means "file without extension" and does
    /// not.
    public static func classify(pathExtension: String?) -> DocumentFormat {
        guard let ext = pathExtension?.lowercased() else { return .markdown }
        if markdownExtensions.contains(ext) { return .markdown }
        if plainTextExtensions.contains(ext) { return .plainText }
        return .other(fileExtension: ext)
    }

    /// Whether the document gets the Markdown treatment: highlighting,
    /// rendered preview, HTML/PDF export. True for Markdown and for plain
    /// text (Fase 4 behavior); the formats new in Fase 6 are edited as
    /// honest plain text.
    public var supportsMarkdown: Bool {
        self == .markdown || self == .plainText
    }

    /// Whether the file's own format is Markdown. The window subtitle
    /// names the format for every document where this is false.
    public var isMarkdown: Bool { self == .markdown }
}
