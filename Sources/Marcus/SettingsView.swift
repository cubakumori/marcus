import SwiftUI

/// How Show Preview (⌘⇧P) presents the rendered document.
enum PreviewMode: String {
    /// Editor and preview side by side.
    case panel
    /// Preview takes the whole window; the editor hides while it's shown.
    case full

    static let defaultsKey = "MarcusPreviewMode"

    static var current: PreviewMode {
        PreviewMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .panel
    }
}

struct SettingsView: View {
    @AppStorage(PreviewMode.defaultsKey) private var previewMode = PreviewMode.panel.rawValue

    var body: some View {
        Form {
            // SwiftUI looks string keys up in the main bundle; ours live in the
            // package's resource bundle, so resolve them explicitly.
            Picker(L("Show Preview in:"), selection: $previewMode) {
                Text(L("Side panel")).tag(PreviewMode.panel.rawValue)
                Text(L("Full window")).tag(PreviewMode.full.rawValue)
            }
            .pickerStyle(.radioGroup)
        }
        .padding(24)
        .frame(width: 340)
    }
}
