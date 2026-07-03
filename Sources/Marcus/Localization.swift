import Foundation

/// Shorthand for a UI string from this target's String Catalog
/// (`Resources/Localizable.xcstrings` — English base, ROADMAP D14).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
