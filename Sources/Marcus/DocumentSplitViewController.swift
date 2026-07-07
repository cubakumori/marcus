import AppKit
import MarcusCore
import MarcusPreview

/// Editor on the left, optional preview on the right. The preview costs
/// nothing while hidden: no parsing, no rendering (manifesto: the editing
/// path never waits).
final class DocumentSplitViewController: NSSplitViewController, NSMenuItemValidation {

    private let document: MarkdownDocument
    private let previewController = PreviewViewController()
    private let outlineController = OutlineViewController()
    private var editorController: EditorViewController!
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    private var outlineItem: NSSplitViewItem!
    private var previewVisible = false
    private var outlineVisible = false

    private var renderGeneration = 0
    private var debounce: DispatchWorkItem?
    private var outlineDebounce: DispatchWorkItem?

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Layer-backed so full-window preview can crossfade (CATransition).
        view.wantsLayer = true
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        outlineItem = NSSplitViewItem(viewController: outlineController)
        outlineItem.minimumThickness = 160
        outlineItem.maximumThickness = 320
        outlineItem.canCollapse = true
        outlineItem.isCollapsed = true
        addSplitViewItem(outlineItem)
        outlineController.onSelect = { [weak self] item in
            self?.editorController.goTo(range: item.range)
        }

        editorController = EditorViewController(document: document)
        editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 320
        editorItem.canCollapse = true
        addSplitViewItem(editorItem)
        editorController.onCaretMove = { [weak self] caret in
            self?.scheduleSync(caret: caret)
        }

        previewItem = NSSplitViewItem(viewController: previewController)
        previewItem.minimumThickness = 280
        previewItem.canCollapse = true
        previewItem.isCollapsed = true
        addSplitViewItem(previewItem)

        previewController.apply(background: EditorTheme.current.palette.background)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidChange(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: document.textStorage
        )
        // Re-apply layout if the preview-mode setting changes while visible.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The subtitle needs the window, which viewDidLoad does not have
        // yet — and Save As can change the format afterwards.
        updateModeIndicator()
        if fileURLObservation == nil {
            fileURLObservation = document.observe(\.fileURL) { [weak self] _, _ in
                Task { @MainActor in self?.updateModeIndicator() }
            }
        }
        // Testability hook: `Marcus doc.md -MarcusDebugShowPreview YES` opens
        // the preview without user interaction (used by automated UI checks).
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowPreview"), !previewVisible {
            togglePreview(nil)
        }
        if UserDefaults.standard.bool(forKey: "MarcusDebugShowOutline"), !outlineVisible {
            toggleOutline(nil)
        }
        // Same idea for PDF export: `Marcus doc.md -MarcusDebugExportPDF /tmp/out.pdf`
        // writes the paginated PDF without touching the save panel.
        if let path = UserDefaults.standard.string(forKey: "MarcusDebugExportPDF"), !debugPDFExported {
            debugPDFExported = true
            document.runPrintJob(.pdfFile(URL(fileURLWithPath: path)))
        }
        // Places the caret at a UTF-16 offset once the first render had
        // time to finish — exercises the caret→preview sync end to end.
        let caretAt = UserDefaults.standard.integer(forKey: "MarcusDebugCaretAt")
        if caretAt > 0, !debugCaretScheduled {
            debugCaretScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.editorController.goTo(range: NSRange(location: caretAt, length: 0))
            }
        }
        // Dumps the preview scroll state as JSON once the sync above had
        // time to run — lets automated checks assert the scroll happened
        // without needing a screenshot.
        if let path = UserDefaults.standard.string(forKey: "MarcusDebugDumpSyncState"),
           !debugSyncDumpScheduled {
            debugSyncDumpScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                guard let self else { return }
                let state = self.previewController.debugScrollState
                let list = self.lastAnchors.map { "[\($0.sourceLine), \($0.location)]" }
                    .joined(separator: ", ")
                let json = "{\"clipOriginY\": \(state.originY), " +
                    "\"documentHeight\": \(state.documentHeight), " +
                    "\"anchors\": [\(list)], " +
                    "\"syncedLocation\": \(self.lastSyncedLocation), " +
                    "\"badge\": \"\(self.previewController.debugBadgeInfo)\"}"
                try? json.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // Dumps the document's identity as JSON after 2 s — format
        // classification, subtitle and count bar (Fase 6), asserted by
        // automated checks without a screenshot.
        if let path = UserDefaults.standard.string(forKey: "MarcusDebugDumpDocState"),
           !debugDocDumpScheduled {
            debugDocDumpScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                let json = "{\"displayName\": \"\(self.document.displayName ?? "")\", " +
                    "\"fileURL\": \"\(self.document.fileURL?.path ?? "")\", " +
                    "\"formatName\": \"\(self.document.format.displayName)\", " +
                    "\"isMarkdown\": \(self.document.format.isMarkdown), " +
                    "\"subtitle\": \"\(self.view.window?.subtitle ?? "")\", " +
                    "\"countBar\": \"\(self.editorController.debugCountBarText)\"}"
                try? json.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // Toggles the preview N seconds after appearing — lets automated
        // checks capture the show/hide transition (e.g. full-window mode).
        let toggleAfter = UserDefaults.standard.double(forKey: "MarcusDebugTogglePreviewAfter")
        if toggleAfter > 0, !debugToggleScheduled {
            debugToggleScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + toggleAfter) { [weak self] in
                self?.togglePreview(nil)
            }
        }
    }

    private var debugPDFExported = false
    private var debugToggleScheduled = false
    private var debugCaretScheduled = false
    private var debugSyncDumpScheduled = false
    private var debugDocDumpScheduled = false
    private var fileURLObservation: NSKeyValueObservation?

    // MARK: - Toggle

    @objc func togglePreview(_ sender: Any?) {
        previewVisible.toggle()
        applyPreviewLayout()
        if previewVisible { scheduleRender(afterDelay: 0) }
    }

    private func applyPreviewLayout() {
        if PreviewMode.current == .full {
            // Full-window mode swaps the whole window between editor and
            // preview, so it crossfades: sliding panes animate to widths
            // that never sum to the window and flash a bare two-pane split.
            crossfade {
                previewItem.isCollapsed = !previewVisible
                editorItem.isCollapsed = previewVisible
            }
        } else {
            // Side panel: the slide reads naturally here; keep it. The
            // editor is restored instantly if full mode left it collapsed
            // (e.g. the setting changed while the preview was visible).
            editorItem.isCollapsed = false
            previewItem.animator().isCollapsed = !previewVisible
        }
        updateModeIndicator()
    }

    /// Full-window preview replaces the editor entirely, so the window
    /// subtitle says which mode it is in while it lasts — plus a discreet
    /// badge on the content, because in macOS full screen the title bar
    /// (and the subtitle with it) auto-hides. Panel mode needs neither:
    /// the editor stays visible next to the preview.
    ///
    /// When the preview indicator is not showing, the subtitle names the
    /// format of non-Markdown documents (Fase 6): a `.txt` announces
    /// itself as plain text because it *is* plain text.
    private func updateModeIndicator() {
        let showing = previewVisible && PreviewMode.current == .full
        let format = document.format
        view.window?.subtitle = showing ? L("Preview")
            : (format.isMarkdown ? "" : format.displayName)
        previewController.setModeBadge(visible: showing,
                                       tint: EditorTheme.current.palette.preview.secondaryText)
    }

    /// Applies a layout change under a dissolving snapshot of the current
    /// content. NOT a `CATransition` on the backing layer: AppKit owns the
    /// layers of layer-backed views, and mutating them detaches the window's
    /// surface from the window server (the window goes blank and off screen).
    private var fadeSnapshot: NSImageView?

    private func crossfade(_ change: () -> Void) {
        // A rapid re-toggle mid-fade must not bake the dissolving snapshot
        // into the next one.
        fadeSnapshot?.removeFromSuperview()
        fadeSnapshot = nil
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            change()
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        let snapshot = NSImageView(frame: view.bounds)
        snapshot.image = image
        snapshot.imageScaling = .scaleAxesIndependently
        snapshot.autoresizingMask = [.width, .height]
        view.addSubview(snapshot, positioned: .above, relativeTo: nil)
        fadeSnapshot = snapshot
        change()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            snapshot.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // AppKit calls this on the main thread; the API just predates
            // the @MainActor annotations, so Swift 6 can't see it.
            MainActor.assumeIsolated {
                snapshot.removeFromSuperview()
                if self?.fadeSnapshot === snapshot { self?.fadeSnapshot = nil }
            }
        })
    }

    private var appliedTheme = EditorTheme.current

    @objc private func defaultsDidChange(_ notification: Notification) {
        if previewVisible { applyPreviewLayout() }
        // The preview follows the editor theme's inks and background.
        let theme = EditorTheme.current
        if theme != appliedTheme {
            appliedTheme = theme
            previewController.apply(background: theme.palette.background)
            if previewVisible { scheduleRender(afterDelay: 0) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePreview(_:)) {
            menuItem.title = previewVisible ? L("Hide Preview") : L("Show Preview")
        }
        if menuItem.action == #selector(toggleOutline(_:)) {
            menuItem.title = outlineVisible ? L("Hide Outline") : L("Show Outline")
        }
        return true
    }

    // MARK: - Outline

    @objc func toggleOutline(_ sender: Any?) {
        outlineVisible.toggle()
        outlineItem.animator().isCollapsed = !outlineVisible
        if outlineVisible { refreshOutline() }
    }

    /// Derives the outline from the highlighter's scan — already fresh after
    /// every edit, so nothing is re-parsed here.
    private func refreshOutline() {
        let text = document.textStorage.string
        let scan = document.highlighter.lastScan ?? MarkdownScanner.scan(text)
        outlineController.show(MarkdownOutline.items(from: scan, in: text))
    }

    private func scheduleOutlineRefresh() {
        guard outlineVisible else { return }
        outlineDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshOutline() }
        outlineDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Editor → preview sync (Fase 5)

    /// Anchors from the last completed render; empty while the preview is
    /// hidden (nothing renders, nothing to sync).
    private var lastAnchors: [PreviewAnchor] = []
    private var lastSyncedLocation = -1
    private var syncDebounce: DispatchWorkItem?

    /// In panel mode, the preview follows the caret by section. Debounced:
    /// selection changes fire on every keystroke. Full-window mode has no
    /// editor on screen, so there is nothing to follow.
    private func scheduleSync(caret: Int) {
        guard previewVisible, PreviewMode.current == .panel, !lastAnchors.isEmpty else { return }
        syncDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSync(caret: caret) }
        syncDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func performSync(caret: Int) {
        guard previewVisible, PreviewMode.current == .panel else { return }
        let text = document.textStorage.string
        let scan = document.highlighter.lastScan ?? MarkdownScanner.scan(text)
        let line = scan.lineNumber(at: caret)
        let location = PreviewSync.location(forSourceLine: line, anchors: lastAnchors)
        // Only move when the target section changes — re-anchoring on every
        // caret step inside a section would fight the preview's own scroll.
        guard location != lastSyncedLocation else { return }
        lastSyncedLocation = location
        previewController.scroll(toCharacterLocation: location)
    }

    // MARK: - Rendering pipeline

    @objc private func storageDidChange(_ notification: Notification) {
        scheduleRender(afterDelay: 0.3)
        scheduleOutlineRefresh()
    }

    private func scheduleRender(afterDelay delay: TimeInterval) {
        guard previewVisible else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startRender() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startRender() {
        renderGeneration += 1
        let generation = renderGeneration
        let text = document.textStorage.string
        let options = PreviewRenderOptions(
            baseURL: document.fileURL?.deletingLastPathComponent(),
            palette: EditorTheme.current.palette.preview
        )
        Task.detached(priority: .userInitiated) {
            let rendered = MarkdownPreviewRenderer.render(text, options: options)
            await MainActor.run { [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.previewController.show(rendered.string)
                self.lastAnchors = rendered.anchors
            }
        }
    }
}
