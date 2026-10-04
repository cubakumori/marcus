import AppKit
import MarcusCore

/// The usual offer at launch when the app runs from Downloads, the
/// Desktop or a disk image: move it to the Applications folder and reopen
/// from there (what LetsMove does for many Mac apps). Keeps one copy on
/// the Mac, so the system Services and Launch Services point at the
/// right one. The user can decline, and decline for good.
///
/// Never shown for the bare executable or build products, nor during
/// automated checks (`-MarcusDebugNoActivate`, `-MarcusSkipMoveToApplications`).
@MainActor
enum MoveToApplications {

    static let suppressKey = "MarcusSuppressMoveToApplications"

    static func offerIfNeeded() {
        let defaults = UserDefaults.standard
        let force = defaults.bool(forKey: "MarcusDebugShowMovePrompt")
        guard !defaults.bool(forKey: "MarcusSkipMoveToApplications"),
              force || !defaults.bool(forKey: "MarcusDebugNoActivate") else { return }
        let bundlePath = Bundle.main.bundleURL.path
        let home = NSHomeDirectory()
        guard force || InstallLocation.shouldOffer(bundlePath: bundlePath, home: home,
                                                    suppressed: defaults.bool(forKey: suppressKey)) else { return }

        if InstallLocation.isTranslocated(bundlePath) {
            // Gatekeeper is running a copy from a hidden read-only place:
            // only the Finder can move the real one.
            let alert = NSAlert()
            alert.messageText = L("Marcus is outside the Applications folder")
            alert.informativeText = L("Drag Marcus to the Applications folder in the Finder and open it from there, so macOS keeps a single copy and finds its Services.")
            alert.addButton(withTitle: L("OK"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = L("Don't ask again")
            alert.runModal()
            if alert.suppressionButton?.state == .on { defaults.set(true, forKey: suppressKey) }
            return
        }

        let alert = NSAlert()
        alert.messageText = L("Marcus is outside the Applications folder")
        alert.informativeText = L("Move it there so macOS keeps a single copy and finds its Services. Marcus will reopen from its new location.")
        alert.addButton(withTitle: L("Move to Applications"))
        alert.addButton(withTitle: L("Don't Move"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("Don't ask again")
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { defaults.set(true, forKey: suppressKey) }
        guard response == .alertFirstButtonReturn else { return }

        do {
            let destination = try move(from: bundlePath, home: home)
            relaunch(from: destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = L("Marcus couldn't be moved")
            failure.runModal()
        }
    }

    /// Moves (or, from a disk image or another disk, copies) the bundle to
    /// `/Applications`, or `~/Applications` when the first is not writable.
    /// An existing copy at the destination goes to the Trash first.
    private static func move(from bundlePath: String, home: String) throws -> URL {
        let fm = FileManager.default
        let destinationPath = InstallLocation.destination(
            for: bundlePath, home: home, systemApplicationsWritable: fm.isWritableFile(atPath: "/Applications"))
        let destination = URL(fileURLWithPath: destinationPath)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destinationPath) {
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        let source = URL(fileURLWithPath: bundlePath)
        if InstallLocation.isOnExternalVolume(bundlePath) {
            try fm.copyItem(at: source, to: destination)
        } else {
            try fm.moveItem(at: source, to: destination)
        }
        return destination
    }

    /// Quits and reopens from the new location with the same documents.
    /// A tiny shell waits for this process to end before calling `open`,
    /// so Launch Services starts the moved copy instead of activating us.
    private static func relaunch(from destination: URL) {
        let documents = NSDocumentController.shared.documents.compactMap(\.fileURL?.path)
        let quoted = ([destination.path] + documents).map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open -a \(quoted[0]) \(quoted.dropFirst().joined(separator: " "))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }
}
