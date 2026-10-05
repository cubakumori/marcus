import Foundation

/// Where Marcus lives on the web, for the Help menu. One place to change
/// if the repository ever moves.
public enum ProjectLinks {

    public static let repository = URL(string: "https://github.com/cubakumori/marcus")!

    /// The CHANGELOG as it stands at a version's tag (`0.11.0` → tag
    /// `v0.11.0`): its first entry is that version's notes. Not the GitHub
    /// release page — since 2026-10-04 versions carry only a tag (ROADMAP,
    /// «Presentación»), and the CHANGELOG exists at every tag, old and new.
    public static func releaseNotesURL(version: String) -> URL {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = trimmed.hasPrefix("v") ? trimmed : "v" + trimmed
        return repository.appendingPathComponent("blob").appendingPathComponent(tag)
            .appendingPathComponent("CHANGELOG.md")
    }

    /// A new issue in the repository.
    public static let newIssueURL = repository.appendingPathComponent("issues").appendingPathComponent("new")
}
