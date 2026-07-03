import AppKit
import MarcusCore

final class MarkdownDocument: NSDocument {

    let textStorage = NSTextStorage()
    let highlighter = MarkdownHighlighter()

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let split = DocumentSplitViewController(document: self)
        let window = NSWindow(contentViewController: split)
        window.setContentSize(NSSize(width: 900, height: 680))
        window.center()
        window.tabbingIdentifier = "MarcusDocument"
        addWindowController(NSWindowController(window: window))
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
            highlighter.highlightAll(textStorage)
        }
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
        alert.messageText = "This file was changed by another application"
        alert.informativeText = "You have unsaved changes in Marcus. Reloading will discard them."
        alert.addButton(withTitle: "Keep My Changes")
        alert.addButton(withTitle: "Reload From Disk")
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
