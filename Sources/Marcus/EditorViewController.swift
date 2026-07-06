import AppKit
import MarcusCore
import MarcusPreview

/// Writing aids (ROADMAP Fase 3) — opt-in: list continuation changes how
/// Return behaves, so it stays off until the user enables it in Settings.
enum WritingAids {
    static let continueListsKey = "MarcusContinueLists"

    @MainActor
    static var continueLists: Bool {
        UserDefaults.standard.bool(forKey: continueListsKey)
    }
}

/// NSTextView that opens Markdown links on ⌘-click (never on plain click:
/// clicking a link in an editor should edit it, not follow it).
final class EditorTextView: NSTextView {

    var openLink: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let target = linkTarget(at: event) {
            openLink?(target)
            return
        }
        super.mouseDown(with: event)
    }

    private func linkTarget(at event: NSEvent) -> String? {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard let storage = textStorage, index < storage.length else { return nil }
        return storage.attribute(.marcusLinkTarget, at: index, effectiveRange: nil) as? String
    }
}

final class EditorViewController: NSViewController, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate, NSMenuItemValidation {

    static let showWordCountKey = "MarcusShowWordCount"

    private let document: MarkdownDocument
    private var textView: EditorTextView!
    private var countBar: NSView!
    private var countLabel: NSTextField!
    private var countDebounce: DispatchWorkItem?
    private var countGeneration = 0

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

        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 780, height: 640), textContainer: container)
        textView.autoresizingMask = [.width]
        textView.allowsUndo = !document.isGuide
        textView.isEditable = !document.isGuide
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

        textView.openLink = { [weak self] target in
            guard let self else { return }
            let base = self.document.fileURL?.deletingLastPathComponent()
            guard let url = URL(string: target, relativeTo: base) else { return }
            NSWorkspace.shared.open(url)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.frame = textView.frame

        // Word-count bar under the editor; hidden (and costing nothing)
        // unless the user shows it from the View menu.
        countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countBar = NSView()
        countBar.addSubview(countLabel)
        NSLayoutConstraint.activate([
            countBar.heightAnchor.constraint(equalToConstant: 22),
            countLabel.trailingAnchor.constraint(equalTo: countBar.trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: countBar.centerYAnchor),
        ])

        let stack = NSStackView(views: [scrollView, countBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.distribution = .fill
        view = stack

        countBar.isHidden = !UserDefaults.standard.bool(forKey: Self.showWordCountKey)
        if !countBar.isHidden { recount() }

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
        scheduleRecount()
    }

    // MARK: - Word count

    @objc func toggleWordCount(_ sender: Any?) {
        let show = countBar.isHidden
        UserDefaults.standard.set(show, forKey: Self.showWordCountKey)
        countBar.isHidden = !show
        if show { recount() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWordCount(_:)) {
            menuItem.title = countBar.isHidden ? L("Show Word Count") : L("Hide Word Count")
        }
        return true
    }

    private func scheduleRecount() {
        guard !countBar.isHidden else { return }
        countDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recount() }
        countDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Counting walks the whole text; keep it off the main thread so a big
    /// document never blocks typing.
    private func recount() {
        countGeneration += 1
        let generation = countGeneration
        let text = document.textStorage.string
        Task.detached(priority: .utility) {
            let counts = TextMetrics.count(text)
            await MainActor.run { [weak self] in
                guard let self, generation == self.countGeneration else { return }
                let format = Bundle.module.localizedString(
                    forKey: "Words: %@ · Characters: %@", value: nil, table: nil)
                self.countLabel.stringValue = String(
                    format: format,
                    NumberFormatter.localizedString(from: NSNumber(value: counts.words), number: .decimal),
                    NumberFormatter.localizedString(from: NSNumber(value: counts.characters), number: .decimal)
                )
            }
        }
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

    /// Copies the selection — or the whole document if there is none — to
    /// the pasteboard as exporter HTML, with the Markdown source as the
    /// plain-text fallback. For pasting with formatting into mail, forums
    /// or blogs.
    @objc func copyAsHTML(_ sender: Any?) {
        let selection = textView.selectedRange()
        let ns = textView.string as NSString
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: ns.length)
        let markdown = ns.substring(with: range)
        let options = HTMLExportOptions(baseURL: document.fileURL?.deletingLastPathComponent())
        // Same reason as the HTML export: rendering can be slow on big
        // documents, so it stays off the main thread.
        Task.detached(priority: .userInitiated) {
            let html = MarkdownHTMLExporter.body(from: markdown, options: options)
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(html, forType: .html)
                pasteboard.setString(markdown, forType: .string)
            }
        }
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

    /// Caret position changes, for the editor→preview sync. Fires on every
    /// click and keystroke; the listener debounces.
    var onCaretMove: ((Int) -> Void)?

    func textViewDidChangeSelection(_ notification: Notification) {
        onCaretMove?(textView.selectedRange().location)
    }

    func textDidChange(_ notification: Notification) {
        document.highlighter.highlightAfterEdit(document.textStorage)
    }

    /// Route text edits through the document's undo manager so the edited
    /// state, save points and the window's dirty indicator stay in sync.
    func undoManager(for view: NSTextView) -> UndoManager? {
        document.undoManager
    }
}
