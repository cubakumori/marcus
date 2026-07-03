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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        AppearanceSetting.current.apply()
    }

    @objc func changeAppearance(_ sender: NSMenuItem) {
        guard let setting = AppearanceSetting(rawValue: sender.representedObject as? String ?? "") else { return }
        setting.apply()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(changeAppearance(_:)) {
            item.state = (item.representedObject as? String == AppearanceSetting.current.rawValue) ? .on : .off
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
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
