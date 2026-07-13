import AppKit
import MarcusCore
import MarcusPreview
import UniformTypeIdentifiers

/// Fase 4 — opt-in: with the setting on, documents opened from Finder or
/// File → Open group as tabs of a single window instead of separate windows.
/// Off (the default), the system-wide tabbing preference rules, as before.
enum WindowTabbing {
    static let openInTabsKey = "MarcusOpenInTabs"

    @MainActor
    static var openInTabs: Bool {
        UserDefaults.standard.bool(forKey: openInTabsKey)
    }
}

final class MarkdownDocument: NSDocument {

    let textStorage = NSTextStorage()
    let highlighter = MarkdownHighlighter()

    /// The bundled guide opens read-only: no editing, no autosave, no
    /// dirty state — it is documentation, not a user file.
    private(set) var isGuide = false

    /// What the file *is*, by extension (Fase 6, D15). Untitled documents
    /// (no file yet) are Markdown; after Save As the type follows the file.
    var format: DocumentFormat {
        DocumentFormat.classify(pathExtension: fileURL?.pathExtension)
    }

    /// Markdown gets highlighted; the formats new in Fase 6 get the honest
    /// plain-text pass. Save As can move a document between the two worlds
    /// (.js → .md), so the editor re-applies this when the file URL changes.
    func applyHighlighting() {
        if format.supportsMarkdown {
            highlighter.highlightAll(textStorage)
        } else {
            highlighter.applyPlain(textStorage)
        }
    }

    /// Export and print interpret the document as Markdown; for the honest
    /// plain-text formats they stay off (printing them *as plain text* was
    /// considered and deferred — see ROADMAP Fase 6).
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let markdownOnly: [Selector] = [
            #selector(exportAsHTML(_:)), #selector(exportAsPDF(_:)),
            #selector(printDocument(_:)),
        ]
        if let action = item.action, markdownOnly.contains(action), !format.supportsMarkdown {
            return false
        }
        return super.validateUserInterfaceItem(item)
    }

    override class var autosavesInPlace: Bool { true }

    func loadGuide(_ text: String) {
        isGuide = true
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
        highlighter.highlightAll(textStorage)
    }

    override var displayName: String! {
        get { isGuide ? L("Marcus Guide") : super.displayName }
        set { super.displayName = newValue }
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        guard !isGuide else { return }
        super.updateChangeCount(change)
    }

    override func makeWindowControllers() {
        let split = DocumentSplitViewController(document: self)
        let window = NSWindow(contentViewController: split)
        window.setContentSize(NSSize(width: 900, height: 680))
        window.center()
        window.tabbingIdentifier = "MarcusDocument"
        if WindowTabbing.openInTabs {
            window.tabbingMode = .preferred
            // Attach explicitly: AppKit's automatic grouping only pairs
            // windows that were both created with .preferred, so a window
            // from before the setting was enabled would never accept tabs.
            if let target = NSApp.orderedWindows.first(where: {
                $0.tabbingIdentifier == "MarcusDocument" && $0.isVisible
            }) {
                target.addTabbedWindow(window, ordered: .above)
            }
        }
        addWindowController(NSWindowController(window: window))
    }

    /// The type follows the file (D15). A document opened from `foo.html`
    /// carries the fileType `public.plain-text` (Fase 6 coerces the types
    /// Marcus does not declare to plain text), whose default extension is
    /// `.txt` — so a plain in-place save would make NSDocument rename
    /// `foo.html` to `foo.txt`, silently moving the user's file. Keep the
    /// file's own extension on in-place saves: the bytes are the same UTF-8
    /// either way, and the file is the source of truth (D11/D15). Save As and
    /// new untitled documents keep the standard behavior.
    override func fileNameExtension(forType typeName: String,
                                    saveOperation: NSDocument.SaveOperationType) -> String? {
        if saveOperation == .saveOperation || saveOperation == .autosaveInPlaceOperation,
           let ext = fileURL?.pathExtension, !ext.isEmpty {
            return ext
        }
        return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = textStorage.string.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        let text = try Self.decode(data)
        // Safe: concurrent document reading is not enabled, so NSDocument
        // always calls this on the main thread.
        MainActor.assumeIsolated {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: text)
            applyHighlighting()
        }
    }

    // MARK: - Export

    @objc func exportAsHTML(_ sender: Any?) {
        guard let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".html"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.writeHTML(to: url)
        }
    }

    private func writeHTML(to url: URL) {
        let text = textStorage.string
        let options = htmlExportOptions
        // Parsing and inlining images can be slow on big documents; keep it
        // off the main thread (the editing path never waits).
        Task.detached(priority: .userInitiated) {
            do {
                let html = MarkdownHTMLExporter.document(from: text, options: options)
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                _ = await MainActor.run { self.presentError(error) }
            }
        }
    }

    @objc func exportAsPDF(_ sender: Any?) {
        guard let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.runPrintJob(.pdfFile(url))
        }
    }

    override func printDocument(_ sender: Any?) {
        runPrintJob(.printPanel)
    }

    func runPrintJob(_ destination: MarkdownPrinter.Destination) {
        let text = textStorage.string
        let options = htmlExportOptions
        let printer = MarkdownPrinter(destination: destination, printInfo: printInfo, window: windowForSheet)
        Task.detached(priority: .userInitiated) {
            let html = MarkdownHTMLExporter.document(from: text, options: options)
            await MainActor.run { printer.run(html: html) }
        }
    }

    private var htmlExportOptions: HTMLExportOptions {
        HTMLExportOptions(
            title: (displayName as NSString).deletingPathExtension,
            baseURL: fileURL?.deletingLastPathComponent()
        )
    }

    // MARK: - External changes

    private var isHandlingExternalChange = false

    /// The file was touched by someone else (another app, a sync client, a
    /// script). Reload silently if we have no unsaved edits; ask otherwise.
    override nonisolated func presentedItemDidChange() {
        Task { @MainActor in self.handleExternalChange() }
    }

    private func handleExternalChange() {
        guard !isHandlingExternalChange, let url = fileURL else { return }
        guard let diskDate = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              let knownDate = fileModificationDate,
              diskDate > knownDate
        else { return }  // our own save, or nothing actually changed

        isHandlingExternalChange = true
        if isDocumentEdited {
            askAboutExternalChange(url)
        } else {
            reload(from: url)
            isHandlingExternalChange = false
        }
    }

    private func askAboutExternalChange(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = L("This file was changed by another application")
        alert.informativeText = L("You have unsaved changes in Marcus. Reloading will discard them.")
        alert.addButton(withTitle: L("Keep My Changes"))
        alert.addButton(withTitle: L("Reload From Disk"))
        let finish = { (response: NSApplication.ModalResponse) in
            if response == .alertSecondButtonReturn { self.reload(from: url) }
            self.isHandlingExternalChange = false
        }
        if let window = windowForSheet {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private func reload(from url: URL) {
        try? revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
        undoManager?.removeAllActions()
    }

    /// UTF-8 first (BOM tolerated), then system encoding detection as fallback.
    /// Output is always written back as UTF-8 without BOM (ROADMAP D11).
    private nonisolated static func decode(_ data: Data) throws -> String {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        if let text = String(data: data, encoding: .utf8) { return text }
        var converted: NSString?
        _ = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        if let text = converted as String? { return text }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
