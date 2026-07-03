import AppKit

/// Read-only rendered view of the document. Display only: all parsing and
/// attributed-string building happens off the main thread before show(_:).
final class PreviewViewController: NSViewController {

    private var textView: NSTextView!

    override func loadView() {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.autoresizingMask = [.width]
        scrollView.hasVerticalScroller = true
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 640)
        self.textView = textView
        view = scrollView
    }

    func show(_ rendered: NSAttributedString) {
        guard let storage = textView.textStorage, let scrollView = view as? NSScrollView else { return }
        // Keep the reading position stable across re-renders.
        let origin = scrollView.contentView.bounds.origin
        storage.setAttributedString(rendered)
        scrollView.documentView?.scroll(origin)
    }
}
