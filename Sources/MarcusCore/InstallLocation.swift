import Foundation

/// Where the app bundle lives, for the "move to Applications" offer at
/// launch (the usual LetsMove behavior). Pure path logic; the app decides
/// what to show and does the moving.
public enum InstallLocation {

    /// Anywhere under `/Applications` or `<home>/Applications`, subfolders
    /// included: a user who files apps in `/Applications/Writing/` is as
    /// installed as anyone.
    public static func isInsideApplications(_ bundlePath: String, home: String) -> Bool {
        let path = normalized(bundlePath)
        let roots = ["/Applications/", normalized(home) + "/Applications/"]
        return roots.contains { path.hasPrefix($0) }
    }

    /// Gatekeeper runs quarantined apps from a read-only random location;
    /// the real bundle is elsewhere and only the Finder can move it.
    public static func isTranslocated(_ bundlePath: String) -> Bool {
        bundlePath.contains("/AppTranslocation/")
    }

    /// Disk images and external disks mount under `/Volumes`: from there
    /// the bundle is copied, not moved (the source may be read-only).
    public static func isOnExternalVolume(_ bundlePath: String) -> Bool {
        normalized(bundlePath).hasPrefix("/Volumes/")
    }

    /// Whether launching from `bundlePath` deserves the offer: a real
    /// `.app` outside Applications, not suppressed by the user, and not a
    /// build product being run from the repository.
    public static func shouldOffer(bundlePath: String, home: String, suppressed: Bool) -> Bool {
        guard !suppressed, bundlePath.hasSuffix(".app") else { return false }
        guard !bundlePath.contains("/.build/"), !bundlePath.contains("/DerivedData/") else { return false }
        return !isInsideApplications(bundlePath, home: home)
    }

    /// `/Applications/<name>.app` when that folder is writable, else the
    /// user's own `~/Applications/<name>.app`.
    public static func destination(for bundlePath: String, home: String, systemApplicationsWritable: Bool) -> String {
        let name = (bundlePath as NSString).lastPathComponent
        let folder = systemApplicationsWritable ? "/Applications" : normalized(home) + "/Applications"
        return folder + "/" + name
    }

    private static func normalized(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p.hasPrefix("/private/") { p = String(p.dropFirst("/private".count)) }
        return p
    }
}
