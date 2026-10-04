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
    @AppStorage(EditorTheme.defaultsKey) private var editorTheme = EditorTheme.system.rawValue
    @AppStorage(WritingAids.continueListsKey) private var continueLists = false
    @AppStorage(WritingAids.tableTabKey) private var tableTab = true
    @AppStorage(WritingAids.wrapSelectionKey) private var wrapSelection = true
    @AppStorage(WritingAids.checkSpellingKey) private var checkSpelling = true
    @AppStorage(SpellingLanguage.defaultsKey) private var spellingLanguage = SpellingLanguage.system
    private let spellingChoices = SpellingLanguage.choices
    @AppStorage(WindowTabbing.openInTabsKey) private var openInTabs = false
    @AppStorage(OpenAnyText.defaultsKey) private var openAnyText = false

    var body: some View {
        Form {
            // SwiftUI looks string keys up in the main bundle; ours live in the
            // package's resource bundle, so resolve them explicitly.
            Picker(L("Show Preview in:"), selection: $previewMode) {
                Text(L("Side panel")).tag(PreviewMode.panel.rawValue)
                Text(L("Full window")).tag(PreviewMode.full.rawValue)
            }
            .pickerStyle(.radioGroup)

            Picker(L("Editor theme:"), selection: $editorTheme) {
                Text(L("System")).tag(EditorTheme.system.rawValue)
                Text(L("Sepia")).tag(EditorTheme.sepia.rawValue)
                Text(L("Midnight")).tag(EditorTheme.midnight.rawValue)
            }
            .pickerStyle(.radioGroup)

            // "System" leaves the checker as macOS has it (usually automatic
            // per paragraph); a fixed language applies to Marcus only.
            Picker(L("Spelling language:"), selection: $spellingLanguage) {
                Text(L("System")).tag(SpellingLanguage.system)
                Divider()
                ForEach(spellingChoices, id: \.id) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
            .pickerStyle(.menu)

            LabeledContent(L("Other settings:")) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(L("Check spelling while typing"), isOn: $checkSpelling)
                    Toggle(L("Continue lists on ⏎"), isOn: $continueLists)
                    Toggle(L("Tab moves between table cells"), isOn: $tableTab)
                    Toggle(L("Wrap the selection when typing * _ ` ~ ["), isOn: $wrapSelection)
                    Toggle(L("Open documents in tabs"), isOn: $openInTabs)
                    Toggle(L("Open any text file"), isOn: $openAnyText)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
