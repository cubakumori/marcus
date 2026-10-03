import AppKit

/// Exports Markdown as RTF — the document Word, Pages and TextEdit open
/// with formatting intact — from the same attributed string the preview
/// renders (ROADMAP, tras v0.8.0 punto 3). AppKit writes it natively: no
/// Pandoc, no dependencies.
///
/// What travels: fonts, bold/italic/strikethrough, colors, indents, line
/// spacing, links (`HYPERLINK` fields) and the code background. What does
/// not: images, which become their alternative text — RTF proper cannot
/// carry them and RTFD is a bundle Word does not open. The look is fixed
/// for paper (`PreviewPalette.paper`, unscaled): neither the editor theme,
/// the zoom nor Dynamic Type follow the document out of the app.
public enum MarkdownRTFExporter {

    /// RTF bytes ready to write to disk. `title` goes to the document's
    /// info block (Word's File → Properties).
    public static func data(from markdown: String, title: String? = nil, baseURL: URL? = nil) throws -> Data {
        let options = PreviewRenderOptions(baseURL: baseURL, palette: .paper, fontScale: 1, imagesAsText: true)
        let string = portableFonts(MarkdownPreviewRenderer.render(markdown, options: options).string)
        var attributes: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
        if let title { attributes[.title] = title }
        return try string.data(from: NSRange(location: 0, length: string.length), documentAttributes: attributes)
    }

    /// The system's own fonts have private names (`.AppleSystemUIFont…`)
    /// that the RTF writer copies verbatim and no other app resolves — Word
    /// would set the code in a proportional fallback. Swapped for installed
    /// families, keeping size and bold/italic: Menlo for monospaced text,
    /// Helvetica Neue for the rest.
    static func portableFonts(_ string: NSAttributedString) -> NSAttributedString {
        let out = NSMutableAttributedString(attributedString: string)
        let manager = NSFontManager.shared
        out.enumerateAttribute(.font, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            guard let font = value as? NSFont, font.fontName.hasPrefix(".") else { return }
            let family = font.isFixedPitch ? "Menlo" : "Helvetica Neue"
            let traits = manager.traits(of: font).intersection([.boldFontMask, .italicFontMask])
            let weight = font.isFixedPitch ? 5 : manager.weight(of: font)
            guard let portable = manager.font(withFamily: family, traits: traits, weight: weight, size: font.pointSize)
            else { return }
            out.addAttribute(.font, value: portable, range: range)
        }
        return out
    }
}
