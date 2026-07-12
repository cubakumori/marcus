import AppKit

/// System text-size (Dynamic Type) support (ROADMAP v0.7.0 — accessibility).
///
/// macOS 15 (Sequoia) added a system-wide Text Size control in
/// Accessibility → Display; `NSFont.preferredFont(forTextStyle:)` scales with
/// it. Marcus keeps its own monospaced editor and reading typography, so
/// rather than adopting text styles wholesale it derives a single scale factor
/// from `.body` and multiplies its own point sizes by it.
///
/// On macOS 14 — and on macOS 15+ at the default setting — the factor is 1:
/// the fonts are untouched, so this is a no-op until the user actually
/// enlarges system text.
@MainActor
enum DynamicType {

    /// The `.body` point size AppKit reports at the default setting (13 pt).
    /// The scale is `preferred .body size / this`, hence 1 when the user has
    /// not enlarged system text.
    private static let referenceBodySize: CGFloat = 13

    static var scale: CGFloat {
        // Debug override: no launch argument can change the system-wide Text
        // Size setting, so this lets automated checks exercise scaling
        // end-to-end (see -MarcusDebugTextScale).
        let override = UserDefaults.standard.double(forKey: "MarcusDebugTextScale")
        if override > 0 { return override }
        return NSFont.preferredFont(forTextStyle: .body).pointSize / referenceBodySize
    }

    /// A point size scaled by the current system text size, rounded to a whole
    /// point for crisp glyphs.
    static func scaled(_ size: CGFloat) -> CGFloat {
        (size * scale).rounded()
    }
}
