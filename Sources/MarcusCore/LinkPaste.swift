import Foundation

/// Pasting a URL over a selection makes it a link (writing aid):
/// `[selection](url)`. Pure logic — the editor supplies the selected text
/// and the pasteboard string, and falls back to a normal paste on nil.
public enum LinkPaste {

    /// Schemes that make a pasted string a link destination. A closed list
    /// on purpose: `Hora:tarde` must not become a link, and `javascript:`
    /// never should.
    static let schemes: Set<String> = ["http", "https", "ftp", "ftps", "mailto", "tel", "file"]
    private static let hierarchical: Set<String> = ["http", "https", "ftp", "ftps", "file"]

    /// The Markdown link that should replace `selection`, or nil when the
    /// paste should proceed as usual: the pasted text is not a URL, the
    /// selection is empty, spans lines, contains brackets (would need
    /// escaping) or is itself a URL (the user is swapping it, not labeling
    /// it). Whitespace at the selection's edges stays outside the link.
    public static func replacement(selection: String, pasted: String) -> String? {
        guard let destination = destination(from: pasted) else { return nil }

        let leading = selection.prefix(while: { $0 == " " || $0 == "\t" })
        let trailing = selection.reversed().prefix(while: { $0 == " " || $0 == "\t" })
        let core = selection.dropFirst(leading.count).dropLast(trailing.count)
        guard !core.isEmpty,
              !core.contains(where: \.isNewline),
              !core.contains("["), !core.contains("]"),
              self.destination(from: String(core)) == nil
        else { return nil }

        return leading + "[" + core + "](" + destination + ")" + String(trailing.reversed())
    }

    /// The pasted text as a link destination, or nil if it is not one URL:
    /// trimmed, no inner whitespace, an allowed scheme, and a host (or an
    /// address after `mailto:`/`tel:`). Unbalanced parentheses would end a
    /// bare CommonMark destination early, so those go in angle brackets.
    static func destination(from pasted: String) -> String? {
        let url = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty,
              url.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !url.contains("<"), !url.contains(">"),
              let colon = url.firstIndex(of: ":")
        else { return nil }
        let scheme = url[..<colon].lowercased()
        guard schemes.contains(scheme) else { return nil }
        let rest = url[url.index(after: colon)...]
        if hierarchical.contains(scheme) {
            guard rest.hasPrefix("//") else { return nil }
            let authority = rest.dropFirst(2).prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
            // `file:///path` has an empty authority by design; the rest need
            // a host.
            guard scheme == "file" ? rest.count > 2 : !authority.isEmpty else { return nil }
        } else {
            guard !rest.isEmpty else { return nil }
        }
        return parenthesesBalanced(url) ? url : "<" + url + ">"
    }

    private static func parenthesesBalanced(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth < 0 { return false }
            }
        }
        return depth == 0
    }
}
