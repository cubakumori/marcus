import AppKit
import MarcusCore

@MainActor
enum MainMenu {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu(), title: "Marcus"))
        mainMenu.addItem(submenu(fileMenu(), title: L("File")))
        mainMenu.addItem(submenu(editMenu(), title: L("Edit")))
        mainMenu.addItem(submenu(formatMenu(), title: L("Format")))
        mainMenu.addItem(submenu(viewMenu(), title: L("View")))
        let windowMenu = self.windowMenu()
        mainMenu.addItem(submenu(windowMenu, title: L("Window")))
        NSApp.windowsMenu = windowMenu
        let helpMenu = self.helpMenu()
        mainMenu.addItem(submenu(helpMenu, title: L("Help")))
        NSApp.helpMenu = helpMenu
        return mainMenu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: L("Help"))
        menu.addItem(item(L("Marcus Guide"), #selector(AppDelegate.showGuide(_:)), "h", [.command, .shift]))
        menu.addItem(.separator())
        // Straight to a section of the guide, heading at the top of the
        // window: the questions people bring to a Help menu, without
        // hunting through the whole manual.
        let sections: [(GuideSection, String)] = [
            (.markdown, L("Markdown Syntax")), (.tables, L("Tables")), (.images, L("Images")),
            (.shortcuts, L("Keyboard Shortcuts")), (.export, L("Export and Share")),
        ]
        for (section, title) in sections {
            let entry = item(title, #selector(AppDelegate.showGuideSection(_:)), "")
            entry.representedObject = section.rawValue
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        // The installed version's release notes and a new issue, on GitHub.
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            menu.addItem(item(L("What's New in Marcus \(version)"), #selector(AppDelegate.showReleaseNotes(_:)), ""))
        } else {
            menu.addItem(item(L("What's New"), #selector(AppDelegate.showReleaseNotes(_:)), ""))
        }
        menu.addItem(item(L("Report a Problem…"), #selector(AppDelegate.reportProblem(_:)), ""))
        return menu
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Marcus")
        menu.addItem(item(L("About Marcus"), #selector(AppDelegate.showAbout(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item(L("Settings…"), #selector(AppDelegate.openSettings(_:)), ","))
        menu.addItem(.separator())
        menu.addItem(item(L("Hide Marcus"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Marcus"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L("File"))
        menu.addItem(item(L("New"), #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item(L("Open…"), #selector(NSDocumentController.openDocument(_:)), "o"))

        let recent = NSMenuItem(title: L("Open Recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: L("Open Recent"))
        recentMenu.addItem(item(L("Clear Menu"), #selector(NSDocumentController.clearRecentDocuments(_:)), ""))
        recent.submenu = recentMenu
        menu.addItem(recent)

        menu.addItem(.separator())
        menu.addItem(item(L("Close"), #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item(L("Save…"), #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item(L("Save As…"), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        menu.addItem(item(L("Revert to Saved"), #selector(NSDocument.revertToSaved(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item(L("Export as HTML…"), #selector(MarkdownDocument.exportAsHTML(_:)), "e", [.command, .shift]))
        menu.addItem(item(L("Export as PDF…"), #selector(MarkdownDocument.exportAsPDF(_:)), ""))
        menu.addItem(item(L("Export as RTF…"), #selector(MarkdownDocument.exportAsRTF(_:)), ""))
        menu.addItem(item(L("Export as Word…"), #selector(MarkdownDocument.exportAsDocx(_:)), ""))
        menu.addItem(.separator())
        // The system share sheet with the exported file (ROADMAP, tras
        // v0.8.0 punto 2); the document decides the format and anchors it.
        let share = NSMenuItem(title: L("Share"), action: nil, keyEquivalent: "")
        let shareMenu = NSMenu(title: L("Share"))
        shareMenu.addItem(item(L("Share as HTML…"), #selector(MarkdownDocument.shareAsHTML(_:)), ""))
        shareMenu.addItem(item(L("Share as PDF…"), #selector(MarkdownDocument.shareAsPDF(_:)), ""))
        shareMenu.addItem(item(L("Share as RTF…"), #selector(MarkdownDocument.shareAsRTF(_:)), ""))
        shareMenu.addItem(item(L("Share as Word…"), #selector(MarkdownDocument.shareAsDocx(_:)), ""))
        share.submenu = shareMenu
        menu.addItem(share)
        menu.addItem(.separator())
        menu.addItem(item(L("Print…"), #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L("Edit"))
        menu.addItem(item(L("Undo"), Selector(("undo:")), "z"))
        menu.addItem(item(L("Redo"), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(L("Cut"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(L("Copy"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(L("Copy as HTML"), #selector(DocumentSplitViewController.copyAsHTML(_:)), "c", [.command, .option]))
        menu.addItem(item(L("Paste"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(L("Select All"), #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = NSMenuItem(title: L("Find"), action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: L("Find"))
        findMenu.addItem(finderItem(L("Find…"), .showFindInterface, "f"))
        findMenu.addItem(finderItem(L("Find and Replace…"), .showReplaceInterface, "f", [.command, .option]))
        findMenu.addItem(finderItem(L("Find Next"), .nextMatch, "g"))
        findMenu.addItem(finderItem(L("Find Previous"), .previousMatch, "g", [.command, .shift]))
        findMenu.addItem(finderItem(L("Use Selection for Find"), .setSearchString, "e"))
        find.submenu = findMenu
        menu.addItem(find)

        // The standard submenu; NSTextView implements and validates these
        // (checkmarks included). Substitutions are left out on purpose:
        // smart quotes and dashes corrupt Markdown source.
        let spelling = NSMenuItem(title: L("Spelling and Grammar"), action: nil, keyEquivalent: "")
        let spellingMenu = NSMenu(title: L("Spelling and Grammar"))
        spellingMenu.addItem(item(L("Show Spelling and Grammar"), #selector(NSText.showGuessPanel(_:)), ":"))
        spellingMenu.addItem(item(L("Check Document Now"), #selector(NSText.checkSpelling(_:)), ";"))
        spellingMenu.addItem(.separator())
        spellingMenu.addItem(item(L("Check Spelling While Typing"),
                                  #selector(NSTextView.toggleContinuousSpellChecking(_:)), ""))
        spellingMenu.addItem(item(L("Check Grammar With Spelling"),
                                  #selector(NSTextView.toggleGrammarChecking(_:)), ""))
        spelling.submenu = spellingMenu
        menu.addItem(spelling)
        return menu
    }

    private static func finderItem(_ title: String, _ action: NSTextFinder.Action, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = item(title, #selector(NSResponder.performTextFinderAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: L("Format"))
        menu.addItem(item(L("Bold"), #selector(EditorViewController.toggleBold(_:)), "b"))
        menu.addItem(item(L("Italic"), #selector(EditorViewController.toggleItalic(_:)), "i"))
        menu.addItem(.separator())
        menu.addItem(item(L("Superscript"), #selector(EditorViewController.toggleSuperscript(_:)), "=", [.control, .command]))
        menu.addItem(item(L("Subscript"), #selector(EditorViewController.toggleSubscript(_:)), "-", [.control, .command]))
        menu.addItem(.separator())
        menu.addItem(item(L("Insert Image…"), #selector(EditorViewController.insertImage(_:)), "i", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(L("Insert Table…"), #selector(EditorViewController.insertMarkdownTable(_:)), "t", [.command, .option]))
        menu.addItem(item(L("Format Table"), #selector(EditorViewController.formatTable(_:)), "t", [.control, .command]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L("View"))
        menu.addItem(item(L("Show Outline"), #selector(DocumentSplitViewController.toggleOutline(_:)), "o", [.command, .shift]))
        menu.addItem(item(L("Show Preview"), #selector(DocumentSplitViewController.togglePreview(_:)), "p", [.command, .shift]))
        menu.addItem(item(L("Show Word Count"), #selector(DocumentSplitViewController.toggleWordCount(_:)), ""))
        menu.addItem(.separator())
        // Zoom (D18) lives in the app delegate: it only writes a default, and
        // from there it is reachable whatever has the focus — the preview's
        // text view in full-window mode included.
        menu.addItem(item(L("Zoom In"), #selector(AppDelegate.zoomIn(_:)), "+"))
        // On US-style layouts "+" needs Shift; ⌘= is the convention (Safari,
        // Xcode) and rides on a hidden twin whose key equivalent stays live.
        let zoomInAlternate = item(L("Zoom In"), #selector(AppDelegate.zoomIn(_:)), "=")
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlternate)
        menu.addItem(item(L("Zoom Out"), #selector(AppDelegate.zoomOut(_:)), "-"))
        menu.addItem(item(L("Actual Size"), #selector(AppDelegate.actualSize(_:)), "0"))
        menu.addItem(.separator())
        let appearance = NSMenuItem(title: L("Appearance"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: L("Appearance"))
        for (title, setting) in [(L("System"), AppearanceSetting.system), (L("Light"), .light), (L("Dark"), .dark)] {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.changeAppearance(_:)), keyEquivalent: "")
            item.representedObject = setting.rawValue
            appearanceMenu.addItem(item)
        }
        appearance.submenu = appearanceMenu
        menu.addItem(appearance)

        let theme = NSMenuItem(title: L("Theme"), action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: L("Theme"))
        for (title, setting) in [(L("System"), EditorTheme.system), (L("Sepia"), .sepia), (L("Midnight"), .midnight)] {
            let item = NSMenuItem(title: title, action: #selector(AppDelegate.changeEditorTheme(_:)), keyEquivalent: "")
            item.representedObject = setting.rawValue
            themeMenu.addItem(item)
        }
        theme.submenu = themeMenu
        menu.addItem(theme)
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L("Window"))
        menu.addItem(item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)), ""))
        return menu
    }
}
