import AppKit
import UniformTypeIdentifiers

/// Fase 6 (D15) — opt-in: with "Open any text file" on, the open panel
/// accepts any file and types Marcus did not declare resolve to plain
/// text. Off (the default), the declared types rule, as always — code
/// and logs already opened by conforming to `public.plain-text`.
enum OpenAnyText {
    static let defaultsKey = "MarcusOpenAnyText"

    @MainActor
    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

/// Installed as the shared controller from main.swift (the first
/// NSDocumentController instantiated becomes `shared`).
final class MarcusDocumentController: NSDocumentController {

    /// Categories that are never text, however hard the user opts in:
    /// a JPEG squeezed through the lossy encoding fallback would show
    /// garbage that autosave could write back over the file.
    private static let neverText: [UTType] = [
        .image, .audiovisualContent, .archive, .executable, .font, .pdf,
    ]

    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?,
        completionHandler: @escaping (Int) -> Void
    ) {
        // nil lifts the filter: the panel accepts any file; whether it is
        // text gets decided when reading it.
        super.beginOpenPanel(openPanel,
                             forTypes: OpenAnyText.enabled ? nil : inTypes,
                             completionHandler: completionHandler)
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        super.runModalOpenPanel(openPanel,
                                forTypes: OpenAnyText.enabled ? nil : types)
    }

    override func typeForContents(of url: URL) throws -> String {
        do {
            let type = try super.typeForContents(of: url)
            // Stock resolution reports the file's own UTI (public.html),
            // not a declared-type match — so a type nobody handles must be
            // caught here, where the document class lookup would fail.
            guard OpenAnyText.enabled, documentClass(forType: type) == nil,
                  !refusesAsText(url) else { return type }
            // If the bytes turn out not to decode as text, the read error
            // is the honest answer (same one as always).
            return "public.plain-text"
        } catch {
            // Types the system cannot resolve at all.
            guard OpenAnyText.enabled, !refusesAsText(url) else { throw error }
            return "public.plain-text"
        }
    }

    private func refusesAsText(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        else { return false }
        return Self.neverText.contains { type.conforms(to: $0) }
    }
}
