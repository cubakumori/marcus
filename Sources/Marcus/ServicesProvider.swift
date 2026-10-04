import AppKit

/// System Services (ROADMAP candidata «imprescindible»): entries in any
/// app's Services menu (right-click → Services) that hand text or files
/// to Marcus. Declared in the Info.plist (`NSServices`), registered by
/// macOS when it sees the bundle; this object just answers the calls. No
/// startup cost beyond installing it.
///
/// - «New Marcus Document with Selection»: the selected text, as plain
///   text, in a new untitled document (nothing is converted to Markdown).
/// - «Open in Marcus»: text and Markdown files selected in Finder.
@MainActor
final class ServicesProvider: NSObject {

    static let shared = ServicesProvider()

    /// `NSMessage` = newDocumentWithSelection in the Info.plist.
    @objc(newDocumentWithSelection:userData:error:)
    func newDocumentWithSelection(_ pasteboard: NSPasteboard, userData: String,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = L("Marcus didn't receive any text.") as NSString
            return
        }
        newDocument(with: text)
    }

    /// `NSMessage` = openInMarcus in the Info.plist.
    @objc(openInMarcus:userData:error:)
    func openInMarcus(_ pasteboard: NSPasteboard, userData: String,
                      error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = L("Marcus didn't receive any file.") as NSString
            return
        }
        open(urls)
    }

    /// A new untitled document holding `text`, shown and brought to the
    /// front. Dirty from the start: it came from outside and is unsaved.
    @discardableResult
    func newDocument(with text: String) -> MarkdownDocument? {
        let controller = NSDocumentController.shared
        guard let document = (try? controller.openUntitledDocumentAndDisplay(true)) as? MarkdownDocument
        else { return nil }
        document.loadText(fromService: text)
        NSApp.activate(ignoringOtherApps: true)
        return document
    }

    func open(_ urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        }
    }
}
