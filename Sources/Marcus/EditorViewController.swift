import AppKit

final class EditorViewController: NSViewController, NSTextViewDelegate {

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
        self.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.frame = textView.frame
        view = scrollView

        document.highlighter.highlightAll(document.textStorage)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
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
