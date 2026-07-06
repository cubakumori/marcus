import AppKit

@MainActor
enum MainMenu {

    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu(), title: "Marcus"))
        mainMenu.addItem(submenu(fileMenu(), title: L("File")))
        mainMenu.addItem(submenu(editMenu(), title: L("Edit")))
        mainMenu.addItem(submenu(viewMenu(), title: L("View")))
        let windowMenu = self.windowMenu()
        mainMenu.addItem(submenu(windowMenu, title: L("Window")))
        NSApp.windowsMenu = windowMenu
        return mainMenu
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
        return menu
    }

    private static func finderItem(_ title: String, _ action: NSTextFinder.Action, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = item(title, #selector(NSResponder.performTextFinderAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L("View"))
        menu.addItem(item(L("Show Outline"), #selector(DocumentSplitViewController.toggleOutline(_:)), "o", [.command, .shift]))
        menu.addItem(item(L("Show Preview"), #selector(DocumentSplitViewController.togglePreview(_:)), "p", [.command, .shift]))
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
