import Foundation

/// The arithmetic behind the in-app text zoom (D18): a factor the user nudges
/// with ⌘+ / ⌘- and resets with ⌘0. Kept pure and here so the clamping and the
/// 0.1 grid are tested without a running app; the UserDefaults-backed store and
/// the live re-apply live in the app layer.
///
/// The factor composes with the system Dynamic Type scale (v0.7.0): the editor
/// and preview use `baseSize × DynamicType.scale × factor`, so the two controls
/// stack instead of fighting.
public enum ZoomStep {

    public static let minimum: Double = 0.5
    public static let maximum: Double = 3.0
    public static let increment: Double = 0.1
    /// The "actual size" ⌘0 returns to.
    public static let normal: Double = 1.0

    /// Bounds to [minimum, maximum] and snaps to the 0.1 grid, so repeated
    /// in/out steps never drift (1.0 → 1.1 → 1.0 is exact, not 0.999…).
    public static func clamp(_ factor: Double) -> Double {
        let bounded = Swift.min(Swift.max(factor, minimum), maximum)
        return (bounded * 10).rounded() / 10
    }

    public static func zoomedIn(_ factor: Double) -> Double { clamp(factor + increment) }
    public static func zoomedOut(_ factor: Double) -> Double { clamp(factor - increment) }
}
