import AppKit

/// The editor's color palette. `system` follows the OS appearance through
/// semantic colors; the other two are fixed papers. Two or three themes,
/// never an ecosystem (ROADMAP, Fase 2).
enum EditorTheme: String, CaseIterable {
    case system, sepia, midnight

    static let defaultsKey = "MarcusEditorTheme"

    @MainActor
    static var current: EditorTheme {
        EditorTheme(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    var palette: EditorPalette {
        switch self {
        case .system:
            EditorPalette(
                text: .labelColor,
                secondaryText: .secondaryLabelColor,
                tertiaryText: .tertiaryLabelColor,
                accent: .controlAccentColor,
                link: .linkColor,
                code: .systemPurple,
                codeBackground: .quaternarySystemFill,
                background: .textBackgroundColor
            )
        case .sepia:
            EditorPalette(
                text: NSColor(srgbRed: 0.28, green: 0.23, blue: 0.16, alpha: 1),
                secondaryText: NSColor(srgbRed: 0.48, green: 0.42, blue: 0.33, alpha: 1),
                tertiaryText: NSColor(srgbRed: 0.65, green: 0.58, blue: 0.47, alpha: 1),
                accent: NSColor(srgbRed: 0.70, green: 0.33, blue: 0.18, alpha: 1),
                link: NSColor(srgbRed: 0.55, green: 0.30, blue: 0.12, alpha: 1),
                code: NSColor(srgbRed: 0.42, green: 0.31, blue: 0.55, alpha: 1),
                codeBackground: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.79, alpha: 1),
                background: NSColor(srgbRed: 0.97, green: 0.95, blue: 0.89, alpha: 1)
            )
        case .midnight:
            EditorPalette(
                text: NSColor(srgbRed: 0.85, green: 0.87, blue: 0.91, alpha: 1),
                secondaryText: NSColor(srgbRed: 0.58, green: 0.63, blue: 0.69, alpha: 1),
                tertiaryText: NSColor(srgbRed: 0.36, green: 0.40, blue: 0.45, alpha: 1),
                accent: NSColor(srgbRed: 0.42, green: 0.71, blue: 1.0, alpha: 1),
                link: NSColor(srgbRed: 0.42, green: 0.71, blue: 1.0, alpha: 1),
                code: NSColor(srgbRed: 0.78, green: 0.57, blue: 0.92, alpha: 1),
                codeBackground: NSColor(srgbRed: 0.10, green: 0.13, blue: 0.16, alpha: 1),
                background: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.10, alpha: 1)
            )
        }
    }
}

struct EditorPalette {
    let text: NSColor
    let secondaryText: NSColor
    let tertiaryText: NSColor
    let accent: NSColor
    let link: NSColor
    let code: NSColor
    let codeBackground: NSColor
    let background: NSColor
}
