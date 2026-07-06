import AppKit

/// App-level appearance override, persisted across launches.
@MainActor
enum AppearanceSetting: String, CaseIterable {
    case system, light, dark

    static let defaultsKey = "MarcusAppearance"

    static var current: AppearanceSetting {
        AppearanceSetting(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowController: NSWindowController?

    @objc func openSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L("Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(sender)
    }

    /// Standard about panel, plus a credits line linking to the repository.
    @objc func showAbout(_ sender: Any?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let credits = NSAttributedString(
            string: "github.com/cubakumori/marcus",
            attributes: [
                .link: URL(string: "https://github.com/cubakumori/marcus")!,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// Opens the bundled guide (manual + live Markdown demo) read-only,
    /// in the user's language. Reuses the window if it is already open.
    @objc func showGuide(_ sender: Any?) {
        if let existing = NSDocumentController.shared.documents
            .compactMap({ $0 as? MarkdownDocument }).first(where: \.isGuide) {
            existing.showWindows()
            return
        }
        let name = Bundle.module.preferredLocalizations.first == "es" ? "Guide.es" : "Guide.en"
        guard let url = Bundle.module.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let document = MarkdownDocument()
        document.loadGuide(text)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        AppearanceSetting.current.apply()
    }

    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard let setting = AppearanceSetting(rawValue: sender.representedObject as? String ?? "") else { return }
        setting.apply()
    }

    /// Same setting as Ajustes → Editor theme; editors and previews react
    /// through UserDefaults.didChangeNotification.
    @objc func changeEditorTheme(_ sender: NSMenuItem) {
        guard let theme = EditorTheme(rawValue: sender.representedObject as? String ?? "") else { return }
        UserDefaults.standard.set(theme.rawValue, forKey: EditorTheme.defaultsKey)
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(changeAppearance(_:)) {
            item.state = (item.representedObject as? String == AppearanceSetting.current.rawValue) ? .on : .off
        }
        if item.action == #selector(changeEditorTheme(_:)) {
            item.state = (item.representedObject as? String == EditorTheme.current.rawValue) ? .on : .off
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // Testability hook (see marcus-verification-workflow): opens the
        // about panel without menu interaction for screenshot checks.
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowAbout") {
            showAbout(nil)
        }
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowSettings") {
            openSettings(nil)
        }
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowGuide") {
            showGuide(nil)
        }
        // Opens files without Finder/menu interaction (comma-separated paths),
        // e.g. to verify that .txt documents open and keep their type.
        if let paths = UserDefaults.standard.string(forKey: "MarcusDebugOpenFile") {
            for path in paths.components(separatedBy: ",") where !path.isEmpty {
                NSDocumentController.shared.openDocument(
                    withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
            }
        }
        // Runs Save As on the frontmost document (after the hooks above had
        // time to open it) so the save panel's format popup can be captured.
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowSaveAs") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
            }
        }
        // Runs Copy as HTML on the frontmost editor so the pasteboard can be
        // inspected from a script.
        if UserDefaults.standard.bool(forKey: "MarcusDebugCopyHTML") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApp.sendAction(#selector(EditorViewController.copyAsHTML(_:)), to: nil, from: nil)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
