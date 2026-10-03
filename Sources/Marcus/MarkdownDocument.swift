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

    /// Exports and sharing interpret the document as Markdown; for the
    /// honest plain-text formats they stay off. Printing is the exception:
    /// those print as plain text (`PlainTextPrinter`).
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let markdownOnly: [Selector] = [
            #selector(exportAsHTML(_:)), #selector(exportAsPDF(_:)),
            #selector(exportAsRTF(_:)),
            #selector(shareAsHTML(_:)), #selector(shareAsPDF(_:)), #selector(shareAsRTF(_:)),
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
        let window = DocumentWindow(contentViewController: split)
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

    /// The file's line terminator style (D11): detected on read, restored
    /// on write. In memory the text is `\n` only. New documents are LF.
    private(set) var lineEnding: LineEnding = .lf

    /// Always UTF-8 without BOM, in the file's own line ending style (D11).
    override func data(ofType typeName: String) throws -> Data {
        TextFile.encode(textStorage.string, lineEnding: lineEnding)
    }

    /// UTF-8 first (BOM tolerated), UTF-16/32 by BOM, then lossless encoding
    /// detection. Binary data and lossy conversions are refused with a clear
    /// error: opening them would let autosave write a damaged copy over the
    /// user's file (D11, D15).
    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        let decoded: TextFile.Decoded
        do {
            decoded = try TextFile.decode(data)
        } catch let error as TextDecodingError {
            throw Self.readError(error)
        }
        // Safe: concurrent document reading is not enabled, so NSDocument
        // always calls this on the main thread.
        MainActor.assumeIsolated {
            lineEnding = decoded.lineEnding
            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: decoded.text)
            applyHighlighting()
        }
    }

    private nonisolated static func readError(_ reason: TextDecodingError) -> Error {
        let suggestion = switch reason {
        case .binary:
            L("It contains binary data, and Marcus edits text only.")
        case .lossy, .undecodable:
            L("Marcus couldn't read it as text without losing characters, so it won't open it rather than risk saving a damaged copy over the original.")
        }
        return NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadCorruptFile.rawValue, userInfo: [
            NSLocalizedDescriptionKey: L("Marcus can't open this file: it isn't text."),
            NSLocalizedRecoverySuggestionErrorKey: suggestion,
        ])
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

    /// File → Export as RTF: the preview's attributed string on paper —
    /// Word, Pages and TextEdit open it with formatting and links; images
    /// travel as their alternative text (`MarkdownRTFExporter`).
    @objc func exportAsRTF(_ sender: Any?) {
        guard let window = windowForSheet else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rtf]
        panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".rtf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.writeRTF(to: url)
        }
    }

    func writeRTF(to url: URL, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let text = textStorage.string
        let options = htmlExportOptions
        Task.detached(priority: .userInitiated) {
            do {
                let data = try MarkdownRTFExporter.data(from: text, title: options.title, baseURL: options.baseURL)
                try data.write(to: url, options: .atomic)
                await MainActor.run { completion?() }
            } catch {
                _ = await MainActor.run { self.presentError(error) }
            }
        }
    }

    override func printDocument(_ sender: Any?) {
        runPrintJob(.printPanel)
    }

    func runPrintJob(_ destination: MarkdownPrinter.Destination, completion: ((Bool) -> Void)? = nil) {
        let text = textStorage.string
        guard format.supportsMarkdown else {
            let printer = PlainTextPrinter(text: text, title: displayName, destination: destination,
                                           printInfo: printInfo, window: windowForSheet)
            printer.completion = completion
            printer.run()
            return
        }
        let options = htmlExportOptions
        let printer = MarkdownPrinter(destination: destination, printInfo: printInfo, window: windowForSheet)
        printer.completion = completion
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

    // MARK: - Share

    /// File → Share: the exported HTML or PDF through the system's share
    /// sheet — Mail, Messages, AirDrop, Notes… — with no transport code of
    /// our own. The file is written to a temporary folder under the
    /// document's own name, so the recipient gets `Notes.pdf`, not a UUID.
    @objc func shareAsHTML(_ sender: Any?) {
        guard windowForSheet != nil else { return }
        let text = textStorage.string
        let options = htmlExportOptions
        do {
            let url = try shareFileURL(pathExtension: "html")
            Task.detached(priority: .userInitiated) {
                do {
                    let html = MarkdownHTMLExporter.document(from: text, options: options)
                    try html.write(to: url, atomically: true, encoding: .utf8)
                    await MainActor.run { self.presentSharingPicker(for: url) }
                } catch {
                    _ = await MainActor.run { self.presentError(error) }
                }
            }
        } catch {
            presentError(error)
        }
    }

    @objc func shareAsPDF(_ sender: Any?) {
        guard windowForSheet != nil else { return }
        do {
            let url = try shareFileURL(pathExtension: "pdf")
            runPrintJob(.pdfFile(url)) { [weak self] success in
                guard success else { return }
                self?.presentSharingPicker(for: url)
            }
        } catch {
            presentError(error)
        }
    }

    @objc func shareAsRTF(_ sender: Any?) {
        guard windowForSheet != nil else { return }
        do {
            let url = try shareFileURL(pathExtension: "rtf")
            writeRTF(to: url) { [weak self] in self?.presentSharingPicker(for: url) }
        } catch {
            presentError(error)
        }
    }

    /// `<tmp>/Marcus Share/<document name>.<ext>`, previous copy removed.
    /// The system purges the temporary folder; the file must outlive the
    /// picker because Mail or AirDrop read it after the choice.
    private func shareFileURL(pathExtension: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Marcus Share", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = (displayName as NSString).deletingPathExtension
        let url = folder.appendingPathComponent(name).appendingPathExtension(pathExtension)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    /// Kept while the sheet is up; released when the user chooses or
    /// dismisses (delegate below).
    private var sharingPicker: NSSharingServicePicker?
    /// For `-MarcusDebugShare`, which cannot click through the sheet: the
    /// file offered and the services the picker proposed for it.
    private(set) var debugSharedFileURL: URL?
    private(set) var debugProposedSharingServices: [String] = []

    /// Anchored under the title bar, where macOS puts the sheet for apps
    /// without a Share toolbar button (TextEdit, Preview).
    private func presentSharingPicker(for url: URL) {
        guard let content = windowForSheet?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        sharingPicker = picker
        debugSharedFileURL = url
        let anchor = NSRect(x: content.bounds.midX - 1, y: content.bounds.maxY - 2, width: 2, height: 2)
        picker.show(relativeTo: anchor, of: content, preferredEdge: .minY)
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
        // Replacing the storage resets the caret and the scroll; put them
        // back (clamped to the new text) so a sync client touching the file
        // does not also move the user.
        let splits = windowControllers.compactMap { $0.contentViewController as? DocumentSplitViewController }
        let positions = splits.map(\.editorPosition)
        try? revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
        undoManager?.removeAllActions()
        for (split, position) in zip(splits, positions) {
            split.editorPosition = position
        }
    }
}

extension MarkdownDocument: @preconcurrency NSSharingServicePickerDelegate {

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              sharingServicesForItems items: [Any],
                              proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        debugProposedSharingServices = proposedServices.map(\.title)
        return proposedServices
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        sharingPicker = nil
    }
}
