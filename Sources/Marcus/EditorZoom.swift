import AppKit
import MarcusCore

/// The in-app text zoom (D18): a single global, persisted factor the user
/// nudges with ⌘+ / ⌘- and resets with ⌘0. It scales the editor and the
/// preview (the reading content), not the UI chrome. Distinct from Dynamic
/// Type (v0.7.0), which is a system-wide accessibility setting applied on
/// relaunch; this one is per-app, instant, and composes on top of it. The
/// arithmetic (clamp, 0.1 grid) is `ZoomStep` in MarcusCore, tested there.
enum EditorZoom {

    static let defaultsKey = "MarcusEditorZoom"

    /// The stored factor, or 1.0 when never set. `object(forKey:)` guards the
    /// "unset" case (0 would otherwise be indistinguishable and clamp to 0.5).
    @MainActor
    static var factor: CGFloat {
        guard UserDefaults.standard.object(forKey: defaultsKey) != nil else {
            return CGFloat(ZoomStep.normal)
        }
        return CGFloat(ZoomStep.clamp(UserDefaults.standard.double(forKey: defaultsKey)))
    }

    @MainActor static func zoomIn() { store(ZoomStep.zoomedIn(Double(factor))) }
    @MainActor static func zoomOut() { store(ZoomStep.zoomedOut(Double(factor))) }
    @MainActor static func reset() { store(ZoomStep.normal) }

    @MainActor
    private static func store(_ value: Double) {
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }
}
