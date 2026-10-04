import Foundation

/// Sections of the bundled guide that the Help menu opens directly. The
/// guide is content, not UI: its headings live in `Guide.es.md` and
/// `Guide.en.md`, so each section knows the exact heading text in every
/// language and is found by matching the document outline — no anchors,
/// no markup in the guide. A test checks that every title exists exactly
/// once in each guide.
public enum GuideSection: String, CaseIterable, Sendable {
    case markdown
    case tables
    case images
    case shortcuts
    case export

    /// Heading text, without the `#` markers, in each guide language.
    public var headingTitles: [String] {
        switch self {
        case .markdown: ["Markdown, con ejemplos", "Markdown, exemplified"]
        case .tables: ["Tablas", "Tables"]
        case .images: ["Imágenes", "Images"]
        case .shortcuts: ["Atajos de teclado", "Keyboard shortcuts"]
        case .export: ["Exportar y compartir", "Export and share"]
        }
    }

    /// The heading line's range in `text`, or nil when the guide has no
    /// such heading (navigation then just opens the guide).
    public func range(in text: String) -> NSRange? {
        let items = MarkdownOutline.items(from: MarkdownScanner.scan(text), in: text)
        return items.first(where: { headingTitles.contains($0.title) })?.range
    }
}
