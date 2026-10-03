import AppKit
import MarcusCore
import MarcusPreview

/// Writing aids (ROADMAP Fase 3) — opt-in: list continuation changes how
/// Return behaves, so it stays off until the user enables it in Settings.
enum WritingAids {
    static let continueListsKey = "MarcusContinueLists"
    /// Spell checking while typing — the system's red underline. On by
    /// default, like every text app on the Mac; persisted here because
    /// NSTextView forgets the toggle with the window. Registered default
    /// in AppDelegate.
    static let checkSpellingKey = "MarcusCheckSpelling"

    @MainActor
    static var continueLists: Bool {
        UserDefaults.standard.bool(forKey: continueListsKey)
    }

    @MainActor
    static var checkSpelling: Bool {
        UserDefaults.standard.bool(forKey: checkSpellingKey)
    }
}

/// NSTextView that opens Markdown links on ⌘-click (never on plain click:
/// clicking a link in an editor should edit it, not follow it).
final class EditorTextView: NSTextView {

    var openLink: ((String) -> Void)?

    /// Whether the Markdown writing aids — a URL pasted over a selection
    /// becomes a link, image files become image links — may write syntax;
    /// the controller answers from the document's format (honest plain text
    /// never gets Markdown syntax written into it).
    var allowsMarkdownAids: () -> Bool = { true }

    /// Inserts image files as Markdown image links over a range; the
    /// controller owns it (it knows the document's folder). False when it
    /// did not take them and the text view should carry on as usual.
    var insertImageFiles: (([URL], NSRange) -> Bool)?

    override func paste(_ sender: Any?) {
        if pasteWrappingLink(from: .general) || pasteImageFiles(from: .general) { return }
        super.paste(sender)
    }

    /// Image files copied in Finder (⌘C) paste as image links instead of
    /// their names. Only when every file is an image: anything else keeps
    /// the usual paste.
    @discardableResult
    func pasteImageFiles(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, allowsMarkdownAids(), let files = imageFiles(on: pasteboard) else { return false }
        return insertImageFiles?(files, selectedRange()) ?? false
    }

    /// Image files dropped from Finder land as image links at the drop
    /// point. Drags from inside the text (moving a selection) are left to
    /// the text view.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isEditable, allowsMarkdownAids(), sender.draggingSource == nil,
           let files = imageFiles(on: sender.draggingPasteboard) {
            let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            if insertImageFiles?(files, NSRange(location: index, length: 0)) == true { return true }
        }
        return super.performDragOperation(sender)
    }

    private func imageFiles(on pasteboard: NSPasteboard) -> [URL]? {
        let files = pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !files.isEmpty, files.allSatisfy(ImageLink.isImage) else { return nil }
        return files
    }

    /// Insert Image… heads the right-click menu too: picking a file there
    /// beats arranging windows side by side to drag one.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard isEditable, allowsMarkdownAids() else { return menu }
        menu.insertItem(NSMenuItem(title: L("Insert Image…"),
                                   action: #selector(EditorViewController.insertImage(_:)), keyEquivalent: ""), at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    /// Writing aid: a URL pasted over a selection becomes `[selection](url)`.
    /// Returns false when the paste should proceed as usual (no selection,
    /// not a URL, …); the decision itself is `LinkPaste`'s. Takes the
    /// pasteboard as a parameter so the verification hook can feed a private
    /// one instead of touching the user's clipboard.
    @discardableResult
    func pasteWrappingLink(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, allowsMarkdownAids() else { return false }
        let selection = selectedRange()
        guard selection.length > 0,
              let pasted = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
        else { return false }
        let selected = (string as NSString).substring(with: selection)
        guard let replacement = LinkPaste.replacement(selection: selected, pasted: pasted) else { return false }
        // The keyboard's own path: undo, delegate callbacks and the caret
        // after the inserted text come with it.
        insertText(replacement, replacementRange: selection)
        return true
    }

    /// Edit → Spelling and Grammar → Check Spelling While Typing (also in the
    /// text view's own context menu): persist the choice so it survives the
    /// window and reaches the other open editors.
    override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        UserDefaults.standard.set(isContinuousSpellCheckingEnabled, forKey: WritingAids.checkSpellingKey)
    }

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
    private var fileURLObservation: NSKeyValueObservation?

    /// For the -MarcusDebugDumpDocState hook: what the count bar shows,
    /// or "(hidden)" — asserting behavior without a screenshot.
    var debugCountBarText: String {
        countBar.isHidden ? "(hidden)" : countLabel.stringValue
    }

    /// Accessibility naming for `-MarcusDebugDumpA11y` — asserts the editor's
    /// and the count bar's VoiceOver labels without VoiceOver itself.
    var debugEditorA11yLabel: String { textView.accessibilityLabel() ?? "" }
    /// For -MarcusDebugDumpDocState: whether the red underline is on.
    var debugSpellChecking: Bool { textView.isContinuousSpellCheckingEnabled }
    var debugCountBarA11yLabel: String {
        countBar.isHidden ? "(hidden)" : (countBar.accessibilityLabel() ?? "")
    }

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
        // Canonical scroll-view text setup: no minimum of its own (the clip
        // dictates the width), unbounded maximum (height grows with text).
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = document.highlighter.theme.typingAttributes

        // Smart substitutions corrupt Markdown source; all off.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        // Checking (underlining) is not correcting: the text is never
        // changed behind the user's back. Persisted setting, on by default.
        textView.isContinuousSpellCheckingEnabled = WritingAids.checkSpelling

        textView.delegate = self
        document.textStorage.delegate = self
        // VoiceOver otherwise names editor and preview alike; distinguish them.
        textView.setAccessibilityLabel(L("Editor"))
        self.textView = textView

        textView.allowsMarkdownAids = { [weak self] in
            self?.document.format.supportsMarkdown ?? false
        }
        textView.insertImageFiles = { [weak self] files, range in
            guard let self, self.document.format.supportsMarkdown else { return false }
            self.insertImages(files, replacing: range)
            return true
        }
        textView.openLink = { [weak self] target in
            guard let self else { return }
            let base = self.document.fileURL?.deletingLastPathComponent()
            guard let url = LinkDestination.url(target, relativeTo: base) else { return }
            NSWorkspace.shared.open(url)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.frame = textView.frame
        // The clip grew from zero to 780 pt with the 780 pt text view already
        // inside, and autoresizing added those 780 on top: the text view
        // stayed that much wider than its clip forever, wrapped far past the
        // window's right edge and scrolled sideways to follow the caret (the
        // first glyphs cut off at the left once the outline and the preview
        // squeezed the editor). Re-align it with the clip once; autoresizing
        // keeps them together from here. Note: do NOT set
        // horizontalScrollElasticity = .none here — with it, NSSplitView can
        // no longer shrink the editor pane and the side panes open at 0 pt.
        textView.frame.size.width = scrollView.contentSize.width

        // Word-count bar under the editor; hidden (and costing nothing)
        // unless the user shows it from the View menu.
        countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: DynamicType.scaled(NSFont.smallSystemFontSize))
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countBar = NSView()
        countBar.addSubview(countLabel)
        // Read as one clean phrase: the visual bar uses "·" separators that
        // VoiceOver would spell out ("middle dot"). The container carries a
        // spoken label (set in recount) and the inner label leaves the tree.
        countLabel.setAccessibilityElement(false)
        countBar.setAccessibilityElement(true)
        countBar.setAccessibilityRole(.staticText)
        NSLayoutConstraint.activate([
            countBar.heightAnchor.constraint(equalToConstant: DynamicType.scaled(22)),
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

        // Save As can change the format (the type follows the file); the
        // highlighting and the bar's format prefix must follow along.
        fileURLObservation = document.observe(\.fileURL) { [weak self] _, _ in
            Task { @MainActor in self?.fileURLDidChange() }
        }

        // The storage was highlighted when the document was read, with the
        // highlighter's theme already at the current palette and zoom; only
        // the view's own chrome is left to set. Re-highlighting here would
        // run the whole document a second time on the open path.
        applyChrome(document.highlighter.theme.palette)

        // Re-theme in place when the setting changes in ⌘, .
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
    }

    // MARK: - Format follows the file (Fase 6)

    private lazy var appliedFormat = document.format

    private func fileURLDidChange() {
        // The first save of an untitled document keeps it Markdown; only a
        // real format flip (Save As .js → .md) pays a full re-style.
        if document.format != appliedFormat {
            appliedFormat = document.format
            document.applyHighlighting()
        }
        if !countBar.isHidden { recount() }
    }

    // MARK: - Theme

    private var appliedTheme = EditorTheme.current
    private var appliedZoom = EditorZoom.factor

    private var appliedSpellingLanguage = SpellingLanguage.current

    @objc private func defaultsDidChange(_ notification: Notification) {
        // Spell checking toggled in Settings or in another window.
        let spelling = WritingAids.checkSpelling
        if textView.isContinuousSpellCheckingEnabled != spelling {
            textView.isContinuousSpellCheckingEnabled = spelling
        }
        // Spelling language changed: re-point the checker and re-check the
        // document so the underlines follow at once (idempotent per window).
        let language = SpellingLanguage.current
        if language != appliedSpellingLanguage {
            appliedSpellingLanguage = language
            SpellingLanguage.apply()
            if textView.isContinuousSpellCheckingEnabled {
                textView.isContinuousSpellCheckingEnabled = false
                textView.isContinuousSpellCheckingEnabled = true
            }
        }
        let theme = EditorTheme.current
        let zoom = EditorZoom.factor
        guard theme != appliedTheme || zoom != appliedZoom else { return }
        appliedTheme = theme
        appliedZoom = zoom
        applyTheme(theme)
    }

    private func applyTheme(_ theme: EditorTheme) {
        let palette = theme.palette
        document.highlighter.theme.palette = palette
        // Zoom (D18) rides in on the same re-apply: set the factor, then the
        // single re-highlight below lays out both the new inks and the new
        // sizes at once.
        document.highlighter.theme.zoom = EditorZoom.factor
        applyChrome(palette)
        document.applyHighlighting()
    }

    /// The text view's own colors and typing attributes for a palette; the
    /// storage's attributes are the highlighter's business.
    private func applyChrome(_ palette: EditorPalette) {
        textView.backgroundColor = palette.background
        textView.insertionPointColor = palette.text
        textView.typingAttributes = document.highlighter.theme.typingAttributes
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Reading position

    /// Caret and scroll, captured before a silent reload (external change)
    /// and restored after it, so the file changing under the user does not
    /// also throw them to the top of the document.
    struct Position {
        let selection: NSRange
        let scrollOrigin: NSPoint
    }

    var position: Position {
        get {
            Position(selection: textView.selectedRange(),
                     scrollOrigin: textView.enclosingScrollView?.contentView.bounds.origin ?? .zero)
        }
        set {
            let length = (textView.string as NSString).length
            let location = min(newValue.selection.location, length)
            let selection = NSRange(location: location,
                                    length: min(newValue.selection.length, length - location))
            textView.setSelectedRange(selection)
            guard let scrollView = textView.enclosingScrollView else { return }
            let clip = scrollView.contentView
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
            clip.setBoundsOrigin(NSPoint(x: 0, y: min(newValue.scrollOrigin.y, maxY)))
            scrollView.reflectScrolledClipView(clip)
        }
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

    var isWordCountVisible: Bool { !countBar.isHidden }

    /// The menu action lives in the split controller (reachable from the
    /// preview and outline too); this is the editor's part.
    func toggleWordCount() {
        let show = countBar.isHidden
        UserDefaults.standard.set(show, forKey: Self.showWordCountKey)
        countBar.isHidden = !show
        if show { recount() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Markdown-interpreting commands stay off for the honest plain-text
        // formats (Fase 6): they would wrap or render syntax the file does
        // not speak.
        let markdownOnly: [Selector?] = [
            #selector(toggleBold(_:)), #selector(toggleItalic(_:)),
            #selector(toggleSuperscript(_:)), #selector(toggleSubscript(_:)),
        ]
        if markdownOnly.contains(menuItem.action) {
            return document.format.supportsMarkdown
        }
        if menuItem.action == #selector(insertImage(_:)) {
            return document.format.supportsMarkdown && textView.isEditable
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
        // Format indicator (Fase 6): the bar names what the file is,
        // before the counts — "Markdown · Words: … · Characters: …".
        let formatName = document.format.displayName
        // Front matter (Fase 7) is metadata, not the document: excluded
        // from the count where Markdown treatment applies, like the preview
        // and exports. Honest plain text has no front matter concept.
        let skipFrontMatter = document.format.supportsMarkdown
        Task.detached(priority: .utility) {
            let counts = TextMetrics.count(text, skippingFrontMatter: skipFrontMatter)
            await MainActor.run { [weak self] in
                guard let self, generation == self.countGeneration else { return }
                let words = NumberFormatter.localizedString(from: NSNumber(value: counts.words), number: .decimal)
                let characters = NumberFormatter.localizedString(from: NSNumber(value: counts.characters), number: .decimal)
                let format = Bundle.module.localizedString(
                    forKey: "Words: %@ · Characters: %@", value: nil, table: nil)
                self.countLabel.stringValue = formatName + " · " + String(format: format, words, characters)
                // VoiceOver reads a spoken version without the "·" separators.
                self.countBar.setAccessibilityLabel(
                    String(format: L("%@: %@ words, %@ characters"), formatName, words, characters))
            }
        }
    }

    // MARK: - Writing aids

    /// Return inside a list item continues the list (or ends it when the
    /// item is empty). Only when the user opted in.
    func textView(_ view: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              WritingAids.continueLists,
              document.format.supportsMarkdown else { return false }
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
    /// or blogs. The menu action is the split controller's, so it also works
    /// while the preview or the outline has the focus.
    func copyAsHTML() {
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

    // MARK: - Images

    /// Format → Insert Image… (⌘⇧I, also on right-click): the open panel
    /// on images, starting in the document's folder; the choice lands as
    /// `![name](relative/path)` with the name selected to type over.
    @objc func insertImage(_ sender: Any?) {
        guard let window = view.window, textView.isEditable else { return }
        guard let folder = documentFolder else {
            askToSaveFirst { [weak self] in self?.insertImage(nil) }
            return
        }
        let range = textView.selectedRange()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.directoryURL = folder
        panel.prompt = L("Insert")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.insertImages(panel.urls, replacing: range)
        }
    }

    private var documentFolder: URL? {
        document.fileURL?.deletingLastPathComponent()
    }

    /// The one path for the menu, ⌘V of Finder files and drops: relative
    /// links need the document's folder, so an untitled document is saved
    /// first (on the user's say-so) and the insertion resumes after.
    func insertImages(_ files: [URL], replacing range: NSRange) {
        guard let folder = documentFolder else {
            askToSaveFirst { [weak self] in self?.insertImages(files, replacing: range) }
            return
        }
        let text = textView.string as NSString
        guard NSMaxRange(range) <= text.length,
              let insertion = ImageLink.insertion(for: files, documentFolder: folder,
                                                  selection: text.substring(with: range))
        else { return }
        view.window?.makeFirstResponder(textView)
        // The keyboard's own path: one undo step, delegate callbacks.
        textView.insertText(insertion.text, replacementRange: range)
        textView.setSelectedRange(NSRange(location: range.location + insertion.selection.location,
                                          length: insertion.selection.length))
    }

    private var afterSave: (() -> Void)?

    private func askToSaveFirst(then action: @escaping () -> Void) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = L("Save the document to insert images")
        alert.informativeText = L("Images are linked by their path from the document's folder, so the document needs a place on disk first.")
        alert.addButton(withTitle: L("Save…"))
        alert.addButton(withTitle: L("Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.afterSave = action
            // After the alert's sheet is gone, or the save panel cannot
            // attach to the window.
            DispatchQueue.main.async {
                self.document.save(withDelegate: self,
                                   didSave: #selector(self.document(_:didSave:contextInfo:)), contextInfo: nil)
            }
        }
    }

    @objc private func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let action = afterSave
        afterSave = nil
        if didSave, document.fileURL != nil { action?() }
    }

    @objc func toggleSuperscript(_ sender: Any?) {
        applyScript(ScriptToggle.superscripted)
    }

    @objc func toggleSubscript(_ sender: Any?) {
        applyScript(ScriptToggle.subscripted)
    }

    /// Transliterates the selection to Unicode super/subscript (D17). Unlike
    /// emphasis this writes plain characters, so there is no marker to insert
    /// with an empty selection: with no selection we act on the word under the
    /// caret (so the caret anywhere in `H2O` subscripts to `H₂O`).
    private func applyScript(_ transform: (String) -> String) {
        let caret = textView.selectedRange()
        var range = caret
        if range.length == 0 {
            range = textView.selectionRange(forProposedRange: caret, granularity: .selectByWord)
            guard range.length > 0 else { return }
        }
        let ns = textView.string as NSString
        let original = ns.substring(with: range)
        let replacement = transform(original)
        // Nothing convertible (e.g. a word with no super/subscript forms):
        // leave the text and the user's selection untouched.
        guard replacement != original else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        textView.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location,
                                          length: (replacement as NSString).length))
    }

    /// For -MarcusDebugSnapshot: the editor's geometry as JSON — clip bounds
    /// origin (a non-zero x means the text is scrolled sideways), the text
    /// view frame against the scroll view, and the container inset.
    var debugGeometry: String {
        let scroll = textView.enclosingScrollView
        let clip = scroll?.contentView.bounds ?? .zero
        return "{\"clipOrigin\": [\(clip.origin.x), \(clip.origin.y)], " +
            "\"clipSize\": [\(clip.width), \(clip.height)], " +
            "\"textViewFrame\": [\(textView.frame.origin.x), \(textView.frame.width)], " +
            "\"scrollFrame\": [\(scroll?.frame.origin.x ?? -1), \(scroll?.frame.width ?? -1)], " +
            "\"inset\": \(textView.textContainerInset.width), " +
            "\"containerWidth\": \(textView.textContainer?.size.width ?? -1), " +
            "\"minSize\": [\(textView.minSize.width), \(textView.minSize.height)], " +
            "\"maxSize\": [\(textView.maxSize.width), \(textView.maxSize.height)], " +
            "\"autoresizingMask\": \(textView.autoresizingMask.rawValue), " +
            "\"translatesMask\": \(textView.translatesAutoresizingMaskIntoConstraints), " +
            "\"clipAutoresizesSubviews\": \(scroll?.contentView.autoresizesSubviews ?? false), " +
            "\"stackWidth\": \(view.frame.width), " +
            "\"windowWidth\": \(view.window?.frame.width ?? -1)}"
    }

    var debugScrollTranslatesMask: Bool {
        textView.enclosingScrollView?.translatesAutoresizingMaskIntoConstraints ?? false
    }

    /// Every horizontal constraint acting on the editor pane and its scroll
    /// and text views — to see who holds the pane's width.
    var debugHorizontalConstraints: [String] {
        var views: [NSView] = [view, textView]
        if let scroll = textView.enclosingScrollView { views.append(scroll); views.append(scroll.contentView) }
        if let wrapper = view.superview { views.append(wrapper) }
        return views.flatMap { v in
            v.constraintsAffectingLayout(for: .horizontal).map { "\(type(of: v)): \($0.description)" }
        }
    }

    /// For -MarcusDebugTypeText: inserts at the caret through insertText, the
    /// keyboard's own path.
    func debugType(_ text: String) {
        view.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    /// For -MarcusDebugApplyScript: sets a selection (a zero length exercises
    /// the word-under-caret path) and runs a super/subscript command, so the
    /// Format-menu wiring can be verified without keyboard interaction.
    func debugApplyScript(variant: String, selection: NSRange) -> String {
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(selection)
        if variant == "sub" { toggleSubscript(nil) } else { toggleSuperscript(nil) }
        return textView.string
    }

    /// For -MarcusDebugPaste: pastes `text` over a selection through the
    /// same code as ⌘V, from a private pasteboard (the user's clipboard is
    /// never read or written). Returns the resulting text, the caret and
    /// whether the paste became a link.
    func debugPaste(_ text: String, selection: NSRange) -> (text: String, caret: Int, linked: Bool) {
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(selection)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.cubakumori.marcus.debug-paste"))
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let linked = textView.pasteWrappingLink(from: pasteboard)
        // Same fallback as paste(_:), which reads the general pasteboard.
        if !linked { textView.readSelection(from: pasteboard) }
        return (textView.string, textView.selectedRange().location, linked)
    }

    /// For -MarcusDebugInsertImage: pastes `files` as if copied in Finder,
    /// through the same code as ⌘V, from a private pasteboard. Returns the
    /// text, the selection and whether a sheet (the save-first alert) is up.
    func debugPasteImages(_ files: [URL], selection: NSRange) -> (text: String, selection: NSRange, handled: Bool, sheet: Bool) {
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(selection)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.cubakumori.marcus.debug-paste"))
        pasteboard.clearContents()
        pasteboard.writeObjects(files as [NSURL])
        let handled = textView.pasteImageFiles(from: pasteboard)
        return (textView.string, textView.selectedRange(), handled, view.window?.attachedSheet != nil)
    }

    // MARK: - NSTextViewDelegate

    /// Caret position changes, for the editor→preview sync. Fires on every
    /// click and keystroke; the listener debounces.
    var onCaretMove: ((Int) -> Void)?

    func textViewDidChangeSelection(_ notification: Notification) {
        onCaretMove?(textView.selectedRange().location)
    }

    func textDidChange(_ notification: Notification) {
        // Honest plain text needs no per-edit pass: typed and pasted text
        // already take the typing attributes (the editor is not rich text).
        guard document.format.supportsMarkdown else { return }
        document.highlighter.highlightAfterEdit(document.textStorage)
    }

    /// Route text edits through the document's undo manager so the edited
    /// state, save points and the window's dirty indicator stay in sync.
    func undoManager(for view: NSTextView) -> UndoManager? {
        document.undoManager
    }
}
