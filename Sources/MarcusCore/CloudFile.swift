import Foundation

/// Files whose bytes live in a cloud provider rather than on disk (iCloud
/// Drive with "Optimize Mac Storage", or any File Provider): macOS marks
/// them *dataless* and the first read blocks until the provider has
/// fetched them — 25 s for a 4 KB file on 2026-10-05 (ROADMAP). Knowing
/// beforehand lets the app say what it is waiting for.
public enum CloudFile {

    /// Whether the file at `url` is currently dataless (`SF_DATALESS` in
    /// its BSD flags). False for files that are not there at all.
    public static func isDataless(_ url: URL) -> Bool {
        var status = stat()
        guard stat(url.path, &status) == 0 else { return false }
        return (status.st_flags & UInt32(SF_DATALESS)) != 0
    }
}
