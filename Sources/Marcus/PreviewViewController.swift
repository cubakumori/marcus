import AppKit

/// Read-only rendered view of the document. Display only: all parsing and
/// attributed-string building happens off the main thread before show(_:).
final class PreviewViewController: NSViewController {

    private var textView: NSTextView!
    private var scrollView: NSScrollView!

    override func loadView() {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.autoresizingMask = [.width]
        scrollView.hasVerticalScroller = true
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 640)
        scrollView.autoresizingMask = [.width, .height]
        self.textView = textView
        self.scrollView = scrollView
        // Plain container so overlays (the mode badge) can use Auto Layout:
        // NSScrollView tiles its own subviews and never lays out foreign
        // ones — a constraint-based subview added to it stays at zero size.
        let container = NSView(frame: scrollView.frame)
        container.addSubview(scrollView)
        view = container
    }

    func apply(background: NSColor) {
        _ = view  // the collapsed split item may not have loaded the view yet
        textView.backgroundColor = background
    }

    // MARK: - Full-window mode badge

    private var modeBadge: NSImageView?

    /// Discreet eye icon pinned to the top-right corner while the preview
    /// owns the whole window. The window subtitle covers the normal case,
    /// but in macOS full screen the title bar auto-hides — the content
    /// itself has to say the editor is hidden. Tinted with the theme's
    /// secondary ink so it reads on any palette.
    func setModeBadge(visible: Bool, tint: NSColor) {
        _ = view
        guard visible else {
            modeBadge?.removeFromSuperview()
            modeBadge = nil
            return
        }
        let badge: NSImageView
        if let existing = modeBadge {
            badge = existing
        } else {
            badge = NSImageView()
            badge.image = NSImage(systemSymbolName: "eye",
                                  accessibilityDescription: L("Preview"))
            badge.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            badge.toolTip = L("Preview")
            badge.setAccessibilityLabel(L("Preview"))
            badge.alphaValue = 0.8
            badge.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
                badge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            ])
            modeBadge = badge
        }
        badge.contentTintColor = tint
    }

    func show(_ rendered: NSAttributedString) {
        guard let storage = textView.textStorage else { return }
        // Keep the reading position stable across re-renders.
        let origin = scrollView.contentView.bounds.origin
        storage.setAttributedString(rendered)
        scrollView.documentView?.scroll(origin)
    }

    /// Scroll position and content height, for the sync verification hook
    /// (`-MarcusDebugDumpSyncState`).
    var debugScrollState: (originY: CGFloat, documentHeight: CGFloat) {
        _ = view
        return (scrollView.contentView.bounds.origin.y,
                scrollView.documentView?.frame.height ?? 0)
    }

    /// First line of what the preview shows, for `-MarcusDebugDumpDocState`
    /// (asserts render vs. honest no-preview message without a screenshot).
    var debugPreviewText: String {
        _ = view
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(80)).replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Badge diagnostics for the same hook.
    var debugBadgeInfo: String {
        guard let badge = modeBadge else { return "no badge" }
        return "frame=\(badge.frame) hidden=\(badge.isHidden) " +
            "hasImage=\(badge.image != nil) inHierarchy=\(badge.superview != nil) " +
            "superviewBounds=\(badge.superview?.bounds ?? .zero)"
    }

    /// Scrolls so the character at `location` (a heading anchor) sits at
    /// the top of the visible area — where a reader expects the section to
    /// land when the editor caret enters it.
    func scroll(toCharacterLocation location: Int) {
        let length = (textView.string as NSString).length
        let target = NSRange(location: max(0, min(location, length)), length: 0)
        // Forces layout up to the target so its fragment frame is real.
        textView.scrollRangeToVisible(target)
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let textLocation = contentManager.location(contentManager.documentRange.location,
                                                         offsetBy: target.location),
              let fragment = layoutManager.textLayoutFragment(for: textLocation)
        else { return }
        let clipView = scrollView.contentView
        let top = fragment.layoutFragmentFrame.minY
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clipView.bounds.height)
        clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, min(top, maxY))))
        scrollView.reflectScrolledClipView(clipView)
    }
}
