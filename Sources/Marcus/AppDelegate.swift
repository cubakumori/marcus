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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

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
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
