import AppKit

/// The document window. NSDocument restores the window itself across
/// relaunches; this subclass adds what Marcus shows inside it — whether the
/// preview and the outline were open — to that same restorable state, so a
/// session comes back as it was left. Nothing is written anywhere else:
/// AppKit's own saved state, no file of ours.
final class DocumentWindow: NSWindow {

    private var panes: DocumentSplitViewController? {
        contentViewController as? DocumentSplitViewController
    }

    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        panes?.encodePaneState(with: coder)
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        panes?.restorePaneState(with: coder)
    }
}
