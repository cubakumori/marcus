import AppKit
import MarcusCore

/// Writing aids (ROADMAP Fase 3) — opt-in: list continuation changes how
/// Return behaves, so it stays off until the user enables it in Settings.
enum WritingAids {
    static let continueListsKey = "MarcusContinueLists"

    @MainActor
    static var continueLists: Bool {
        UserDefaults.standard.bool(forKey: continueListsKey)
    }
}

final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {

    private let document: MarkdownDocument
    private var textView: NSTextView!

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        // Explicit TextKit 2 stack wired to the document's storage (ROADMAP D2).
        let contentStorage = NSTextContentStorage()
        contentStorage.textStorage = document.textStorage
        let layoutManager = NSTextLayoutManager()
        contentStorage.addTextLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.textContainer = container

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 780, height: 640), textContainer: container)
        textView.autoresizingMask = [.width]
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 20, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = document.highlighter.theme.typingAttributes

        // Smart substitutions corrupt Markdown source; all off.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        textView.delegate = self
        document.textStorage.delegate = self
        self.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.frame = textView.frame
        view = scrollView

        applyTheme(EditorTheme.current)

        // Re-theme in place when the setting changes in ⌘, .
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
    }

    // MARK: - Theme

    private var appliedTheme = EditorTheme.current

    @objc private func defaultsDidChange(_ notification: Notification) {
        let theme = EditorTheme.current
        guard theme != appliedTheme else { return }
        appliedTheme = theme
        applyTheme(theme)
    }

    private func applyTheme(_ theme: EditorTheme) {
        let palette = theme.palette
        document.highlighter.theme.palette = palette
        textView.backgroundColor = palette.background
        textView.insertionPointColor = palette.text
        textView.typingAttributes = document.highlighter.theme.typingAttributes
        document.highlighter.highlightAll(document.textStorage)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    /// Jump to a range (outline navigation): caret there, scrolled into
    /// view, with the system find indicator flash for orientation.
    func goTo(range: NSRange) {
        guard NSMaxRange(range) <= (textView.string as NSString).length else { return }
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollRangeToVisible(range)
        view.window?.makeFirstResponder(textView)
        textView.showFindIndicator(for: range)
    }

    // MARK: - NSTextStorageDelegate

    /// Records each character edit so the highlighter can re-scan
    /// incrementally from the edited line instead of the whole document.
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        document.highlighter.noteEdit(range: editedRange, delta: delta)
    }

    // MARK: - Writing aids

    /// Return inside a list item continues the list (or ends it when the
    /// item is empty). Only when the user opted in.
    func textView(_ view: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              WritingAids.continueLists else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        guard let action = ListContinuation.actionForReturn(in: ns.substring(with: lineRange)) else {
            return false
        }
        switch action {
        case .insert(let marker):
            textView.insertText("\n" + marker, replacementRange: selection)
        case .endList(let markerRange):
            let absolute = NSRange(location: lineRange.location + markerRange.location,
                                   length: markerRange.length)
            guard NSMaxRange(absolute) <= ns.length else { return false }
            if textView.shouldChangeText(in: absolute, replacementString: "") {
                textView.replaceCharacters(in: absolute, with: "")
                textView.didChangeText()
            }
        }
        return true
    }

    @objc func toggleBold(_ sender: Any?) {
        toggleEmphasis("**")
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggleEmphasis("*")
    }

    private func toggleEmphasis(_ delimiter: String) {
        let selection = textView.selectedRange()
        let ns = textView.string as NSString
        if selection.length == 0 {
            // No selection: insert the pair and leave the caret inside.
            let pair = delimiter + delimiter
            guard textView.shouldChangeText(in: selection, replacementString: pair) else { return }
            textView.replaceCharacters(in: selection, with: pair)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selection.location + delimiter.count, length: 0))
            return
        }
        let replacement = EmphasisToggle.toggled(ns.substring(with: selection), delimiter: delimiter)
        guard textView.shouldChangeText(in: selection, replacementString: replacement) else { return }
        textView.replaceCharacters(in: selection, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: selection.location,
                                          length: (replacement as NSString).length))
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        document.highlighter.highlightAfterEdit(document.textStorage)
    }

    /// Route text edits through the document's undo manager so the edited
    /// state, save points and the window's dirty indicator stay in sync.
    func undoManager(for view: NSTextView) -> UndoManager? {
        document.undoManager
    }
}
