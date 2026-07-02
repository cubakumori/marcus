import AppKit
import MarcusCore

final class MarkdownDocument: NSDocument {

    let textStorage = NSTextStorage()
    let highlighter = MarkdownHighlighter()

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let editor = EditorViewController(document: self)
        let window = NSWindow(contentViewController: editor)
        window.setContentSize(NSSize(width: 780, height: 640))
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
