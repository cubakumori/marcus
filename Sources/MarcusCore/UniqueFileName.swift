import Foundation

/// File names for documents created from outside the app (Shortcuts): a
/// safe name with the right extension, and a free one when it is taken —
/// Marcus never overwrites a file the user did not point at.
public enum UniqueFileName {

    /// A Markdown file name from whatever the user typed: path separators
    /// and colons dropped, surrounding whitespace trimmed, `.md` added
    /// unless the name already carries a Markdown extension; empty input
    /// becomes `Untitled.md`.
    public static func markdownFileName(from name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.isEmpty { cleaned = "Untitled" }
        let ext = (cleaned as NSString).pathExtension.lowercased()
        if DocumentFormat.classify(pathExtension: ext) == .markdown, !ext.isEmpty {
            return cleaned
        }
        return cleaned + ".md"
    }

    /// `proposed` if free, otherwise `name 2.ext`, `name 3.ext`… — the
    /// Finder convention — up to the first free one.
    public static func available(_ proposed: String, exists: (String) -> Bool) -> String {
        guard exists(proposed) else { return proposed }
        let ns = proposed as NSString
        let base = ns.deletingPathExtension
        let ext = ns.pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}
