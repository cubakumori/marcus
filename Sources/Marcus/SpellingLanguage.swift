import AppKit

/// The language the spell checker uses, per app (Settings → Spelling
/// language). The system's "Automatic by Language" identifies the language
/// paragraph by paragraph and mis-guesses short, symbol-heavy lines — a
/// heading like `# idyoma & ortografia` reads as Hungarian and goes
/// unmarked. Fixing a language here fixes that for Marcus only: the shared
/// NSSpellChecker is per process, and setting it programmatically does not
/// touch the system-wide preference (verified: no global default written).
@MainActor
enum SpellingLanguage {

    static let defaultsKey = "MarcusSpellingLanguage"
    /// Empty value: leave the checker exactly as the system has it.
    static let system = ""

    static var current: String {
        UserDefaults.standard.string(forKey: defaultsKey) ?? system
    }

    /// The checker's state at launch, before Marcus touched it — what
    /// "System" restores (the user may have fixed a language system-wide).
    private static var systemState: (automatic: Bool, language: String)?

    static func apply() {
        let checker = NSSpellChecker.shared
        if systemState == nil {
            systemState = (checker.automaticallyIdentifiesLanguages, checker.language())
        }
        let code = current
        if code.isEmpty, let state = systemState {
            checker.automaticallyIdentifiesLanguages = state.automatic
            if !state.automatic { _ = checker.setLanguage(state.language) }
        } else if !code.isEmpty {
            checker.automaticallyIdentifiesLanguages = false
            _ = checker.setLanguage(code)
        }
    }

    /// Languages the system can check, named in the user's language and
    /// sorted by that name — for the Settings popup.
    static var choices: [(id: String, name: String)] {
        let locale = Locale.current
        return NSSpellChecker.shared.availableLanguages
            .map { (id: $0, name: locale.localizedString(forIdentifier: $0) ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// For -MarcusDebugDumpDocState.
    static var debugDescription: String {
        let checker = NSSpellChecker.shared
        return checker.automaticallyIdentifiesLanguages ? "automatic" : checker.language()
    }
}
