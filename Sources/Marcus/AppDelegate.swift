import AppKit
import MarcusCore

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
        openGuide()
    }

    /// Help → a section (the menu item carries the `GuideSection` raw
    /// value; the debug hook passes it as a string): the guide, with that
    /// heading at the top of the window.
    @objc func showGuideSection(_ sender: Any?) {
        let raw = (sender as? NSMenuItem)?.representedObject as? String ?? sender as? String
        guard let raw, let section = GuideSection(rawValue: raw), let document = openGuide() else { return }
        document.reveal(section)
    }

    /// The GitHub release of the installed version — its notes are the
    /// CHANGELOG entry — in the browser.
    @objc func showReleaseNotes(_ sender: Any?) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        NSWorkspace.shared.open(ProjectLinks.releaseNotesURL(version: version))
    }

    @objc func reportProblem(_ sender: Any?) {
        NSWorkspace.shared.open(ProjectLinks.newIssueURL)
    }

    @discardableResult
    private func openGuide() -> MarkdownDocument? {
        if let existing = NSDocumentController.shared.documents
            .compactMap({ $0 as? MarkdownDocument }).first(where: \.isGuide) {
            existing.showWindows()
            return existing
        }
        let name = Bundle.module.preferredLocalizations.first == "es" ? "Guide.es" : "Guide.en"
        guard let url = Bundle.module.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let document = MarkdownDocument()
        document.loadGuide(text)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        return document
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Settings that default to on (the rest default to false, which
        // UserDefaults already returns for a missing key).
        UserDefaults.standard.register(defaults: [WritingAids.checkSpellingKey: true, WritingAids.tableTabKey: true])
        SpellingLanguage.apply()
        NSApp.mainMenu = MainMenu.build()
        AppearanceSetting.current.apply()
        // System Services (right-click → Services in any app); the entries
        // live in the Info.plist, this object answers them.
        NSApp.servicesProvider = ServicesProvider.shared
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

    // MARK: - Text zoom (D18)

    /// The zoom factor is a global default; editors and previews react to
    /// the change themselves. Handled here, at the end of the responder
    /// chain, so ⌘+/⌘-/⌘0 work with any focus — the editor, the preview's
    /// read-only text view in full-window mode, or the outline.
    @objc func zoomIn(_ sender: Any?) { EditorZoom.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { EditorZoom.zoomOut() }
    @objc func actualSize(_ sender: Any?) { EditorZoom.reset() }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(changeAppearance(_:)) {
            item.state = (item.representedObject as? String == AppearanceSetting.current.rawValue) ? .on : .off
        }
        if item.action == #selector(changeEditorTheme(_:)) {
            item.state = (item.representedObject as? String == EditorTheme.current.rawValue) ? .on : .off
        }
        return true
    }

    /// Milliseconds from exec to now, off the kernel's process start time —
    /// what the user actually waits, measured without a profiler attached.
    private static func millisecondsSinceProcessStart() -> Double {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return -1 }
        let start = info.kp_proc.p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return (Date().timeIntervalSince1970 - started) * 1000
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Services without the Services menu: `-MarcusDebugServiceText
        // "texto;/out.json"` feeds the text through a private pasteboard
        // as the system would and dumps the new document's text and
        // dirty state; `-MarcusDebugServiceOpen "/a.md,/b.txt;/out.json"`
        // does the same with file URLs and dumps the open documents' names.
        if let spec = UserDefaults.standard.string(forKey: "MarcusDebugServiceText") {
            let parts = spec.components(separatedBy: ";")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard parts.count == 2 else { return }
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.cubakumori.marcus.debug-service"))
                pasteboard.clearContents()
                pasteboard.setString(parts[0].replacingOccurrences(of: "\\n", with: "\n"), forType: .string)
                var message: NSString = ""
                ServicesProvider.shared.newDocumentWithSelection(pasteboard, userData: "", error: &message)
                let document = NSDocumentController.shared.currentDocument as? MarkdownDocument
                let text = (document?.textStorage.string ?? "").replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
                let json = "{\"text\": \"\(text)\", \"edited\": \(document?.isDocumentEdited ?? false), " +
                    "\"untitled\": \(document?.fileURL == nil), \"error\": \"\(message)\", " +
                    "\"documents\": \(NSDocumentController.shared.documents.count)}"
                try? json.write(toFile: parts[1], atomically: true, encoding: .utf8)
            }
        }
        if let spec = UserDefaults.standard.string(forKey: "MarcusDebugServiceOpen") {
            let parts = spec.components(separatedBy: ";")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard parts.count == 2 else { return }
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.cubakumori.marcus.debug-service"))
                pasteboard.clearContents()
                pasteboard.writeObjects(parts[0].components(separatedBy: ",").map { URL(fileURLWithPath: $0) as NSURL })
                var message: NSString = ""
                ServicesProvider.shared.openInMarcus(pasteboard, userData: "", error: &message)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let names = NSDocumentController.shared.documents.map { "\"\($0.displayName ?? "")\"" }
                    let json = "{\"documents\": [\(names.joined(separator: ", "))], \"error\": \"\(message)\"}"
                    try? json.write(toFile: parts[1], atomically: true, encoding: .utf8)
                }
            }
        }
        // Audit hook (ROADMAP transversal): dumps cold-launch timings as
        // JSON — launch end and first main-loop idle (the editor is ready
        // to type) — so every phase can re-check the <500 ms budget
        // without an Instruments session.
        if let path = UserDefaults.standard.string(forKey: "MarcusDebugDumpLaunchTime") {
            let launched = Self.millisecondsSinceProcessStart()
            DispatchQueue.main.async {
                let idle = Self.millisecondsSinceProcessStart()
                let json = "{\"msToDidFinishLaunching\": \(launched), \"msToFirstIdle\": \(idle)}"
                try? json.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // Verification hook: launching Marcus mid-check must not steal the
        // focus — a foreground Marcus swallows whatever the user is typing
        // in another app, and autosave persists it into the open document.
        if !UserDefaults.standard.bool(forKey: "MarcusDebugNoActivate") {
            NSApp.activate(ignoringOtherApps: true)
        }
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
        // Help → section without the menu (`tables`, `images`, …); the
        // landing is checked with -MarcusDebugDumpSyncState (editorCaret,
        // clipOriginY).
        if let section = UserDefaults.standard.string(forKey: "MarcusDebugShowGuideSection") {
            showGuideSection(section)
        }
        // Opens files without Finder/menu interaction (comma-separated paths),
        // e.g. to verify that .txt documents open and keep their type.
        if let paths = UserDefaults.standard.string(forKey: "MarcusDebugOpenFile") {
            for path in paths.components(separatedBy: ",") where !path.isEmpty {
                NSDocumentController.shared.openDocument(
                    withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
            }
        }
        // Same as MarcusDebugOpenFile, but 2.5 s after launch: simulates the
        // Finder / odoc path (opening a document while the app is already
        // running), which is where window tabbing decisions happen.
        if let paths = UserDefaults.standard.string(forKey: "MarcusDebugOpenFileDelayed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                for path in paths.components(separatedBy: ",") where !path.isEmpty {
                    NSDocumentController.shared.openDocument(
                        withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
                }
            }
        }
        // Runs Save As on the frontmost document (after the hooks above had
        // time to open it) so the save panel's format popup can be captured.
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowSaveAs") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApp.sendAction(#selector(NSDocument.saveAs(_:)), to: nil, from: nil)
            }
        }
        // Quits cleanly N seconds after launch — through NSApp.terminate, so
        // AppKit saves the restorable state — to verify session restoration
        // on the next launch.
        let quitAfter = UserDefaults.standard.double(forKey: "MarcusDebugQuitAfter")
        if quitAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                NSApp.terminate(nil)
            }
        }
        // Saves the frontmost document N seconds after launch — after a hook
        // such as -MarcusDebugApplyScript edited it — so the bytes written
        // (encoding, line endings) can be checked from a script.
        let saveAfter = UserDefaults.standard.double(forKey: "MarcusDebugSaveAfter")
        if saveAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + saveAfter) {
                // Addressed directly: with -MarcusDebugNoActivate there is no
                // key window, so a nil-targeted action would go nowhere.
                NSDocumentController.shared.documents
                    .first(where: { $0.fileURL != nil })?.save(nil)
            }
        }
        // Runs Copy as HTML on the frontmost editor so the pasteboard can be
        // inspected from a script.
        if UserDefaults.standard.bool(forKey: "MarcusDebugCopyHTML") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApp.sendAction(#selector(DocumentSplitViewController.copyAsHTML(_:)), to: nil, from: nil)
            }
        }
        // Last, once the windows are up: the offer to move to Applications
        // when running from Downloads, the Desktop or a disk image. A few
        // string checks — nothing the launch budget notices. Forced with
        // `-MarcusDebugShowMovePrompt YES`, silenced with
        // `-MarcusSkipMoveToApplications YES`.
        DispatchQueue.main.async { MoveToApplications.offerIfNeeded() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
