import Foundation

/// Where Marcus lives on the web, for the Help menu. One place to change
/// if the repository ever moves.
public enum ProjectLinks {

    public static let repository = URL(string: "https://github.com/cubakumori/marcus")!

    /// The GitHub release of a given version (`0.11.0` → tag `v0.11.0`),
    /// whose notes are the CHANGELOG entry for it.
    public static func releaseNotesURL(version: String) -> URL {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = trimmed.hasPrefix("v") ? trimmed : "v" + trimmed
        return repository.appendingPathComponent("releases").appendingPathComponent("tag")
            .appendingPathComponent(tag)
    }

    /// A new issue in the repository.
    public static let newIssueURL = repository.appendingPathComponent("issues").appendingPathComponent("new")
}
