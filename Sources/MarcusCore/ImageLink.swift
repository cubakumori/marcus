import Foundation

/// Inserting images as Markdown (writing aid): Format → Insert Image…,
/// pasting image files copied in Finder, and dropping them on the editor
/// all end here. Pure logic — the editor supplies the files, the document's
/// folder and the selected text, and inserts what comes back. Nothing is
/// copied anywhere: the link points at the file where it already is.
public enum ImageLink {

    /// File extensions treated as images — what Markdown renderers (and the
    /// preview) display; the rest of the files keep the editor's usual
    /// paste and drop.
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif", "tif", "tiff", "bmp", "avif",
    ]

    public static func isImage(_ file: URL) -> Bool {
        file.isFileURL && extensions.contains(file.pathExtension.lowercased())
    }

    /// The Markdown to insert and, inside it, the range (UTF-16) to select
    /// afterwards: the first image's alternative text when it came from the
    /// file name — so typing replaces it with a real description —, or an
    /// empty range after the text when the selection became the
    /// description. One image per line; nil when `files` holds no image.
    public static func insertion(for files: [URL], documentFolder: URL, selection: String)
        -> (text: String, selection: NSRange)? {
        let images = files.filter(isImage)
        guard !images.isEmpty else { return nil }
        let described = images.count == 1 && !selection.isEmpty && !selection.contains(where: \.isNewline)
        var text = ""
        var altRange = NSRange(location: NSNotFound, length: 0)
        for (index, image) in images.enumerated() {
            if index > 0 { text += "\n" }
            let alt = escaped(described ? selection : image.deletingPathExtension().lastPathComponent)
            if index == 0 { altRange = NSRange(location: (text as NSString).length + 2, length: (alt as NSString).length) }
            text += "![" + alt + "](" + destination(of: image, from: documentFolder) + ")"
        }
        let end = NSRange(location: (text as NSString).length, length: 0)
        return (text, described || images.count > 1 ? end : altRange)
    }

    /// The path from `folder` to `file` (`../` when it lives elsewhere), as
    /// a CommonMark link destination: spaces, brackets, parentheses, angle
    /// brackets, `%` and control characters percent-encoded so every
    /// renderer reads it whole; letters — accented ones included — stay
    /// legible.
    static func destination(of file: URL, from folder: URL) -> String {
        let target = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        // The file's own name never counts as a shared folder.
        while common < base.count, common < target.count - 1, target[common] == base[common] {
            common += 1
        }
        let ups = Array(repeating: "..", count: base.count - common)
        // File-system paths come decomposed (NFD: `n` + combining tilde);
        // composed (NFC) reads as typed and is what git stores on the Mac.
        let path = (ups + target[common...]).joined(separator: "/").precomposedStringWithCanonicalMapping
        var encoded = ""
        for scalar in path.unicodeScalars {
            if mustEncode(scalar) {
                for byte in String(scalar).utf8 { encoded += String(format: "%%%02X", byte) }
            } else {
                encoded.unicodeScalars.append(scalar)
            }
        }
        return encoded
    }

    /// What would end or split a CommonMark destination, or be read as an
    /// escape: `addingPercentEncoding` is no use here, it encodes every
    /// non-ASCII byte and `año` would come out as `a%C3%B1o`.
    private static func mustEncode(_ scalar: Unicode.Scalar) -> Bool {
        "()[]<>%\\".unicodeScalars.contains(scalar)
            || scalar.properties.isWhitespace
            || scalar.properties.generalCategory == .control
    }

    /// Brackets would end the alternative text early.
    private static func escaped(_ alt: String) -> String {
        alt.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
