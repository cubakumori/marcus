import AppKit
import MarcusCore
import MarcusPreview

/// Editor on the left, optional preview on the right. The preview costs
/// nothing while hidden: no parsing, no rendering (manifesto: the editing
/// path never waits).
final class DocumentSplitViewController: NSSplitViewController, NSMenuItemValidation {

    private let document: MarkdownDocument
    // Preview and outline are built on first toggle, never at launch: a
    // collapsed pane must not cost its view hierarchy on the typing path
    // (manifesto; startup audit after Fase 6).
    private var previewController: PreviewViewController?
    private var outlineController: OutlineViewController?
    private var editorController: EditorViewController!
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem?
    private var outlineItem: NSSplitViewItem?
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

        editorController = EditorViewController(document: document)
        editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = 320
        editorItem.canCollapse = true
        addSplitViewItem(editorItem)
        editorController.onCaretMove = { [weak self] caret in
            self?.scheduleSync(caret: caret)
        }

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
                let state: (originY: CGFloat, documentHeight: CGFloat) =
                    self.previewController?.debugScrollState ?? (originY: 0, documentHeight: 0)
                let list = self.lastAnchors.map { "[\($0.sourceLine), \($0.location)]" }
                    .joined(separator: ", ")
                let json = "{\"clipOriginY\": \(state.originY), " +
                    "\"documentHeight\": \(state.documentHeight), " +
                    "\"anchors\": [\(list)], " +
                    "\"syncedLocation\": \(self.lastSyncedLocation), " +
                    "\"badge\": \"\(self.previewController?.debugBadgeInfo ?? "no preview")\"}"
                try? json.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // Applies a super/subscript command (D17) to a range — or the word at
        // a caret when the length is 0 — and dumps the resulting document text,
        // so the Format-menu wiring (selection handling, word-at-caret, toggle)
        // is verifiable without keyboard interaction. Value:
        // "super|sub;loc,len;/out.json".
        if let spec = UserDefaults.standard.string(forKey: "MarcusDebugApplyScript"),
           !debugScriptApplied {
            debugScriptApplied = true
            let parts = spec.components(separatedBy: ";")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, parts.count == 3,
                      case let loc = parts[1].components(separatedBy: ","),
                      loc.count == 2, let l = Int(loc[0]), let n = Int(loc[1]) else { return }
                let text = self.editorController.debugApplyScript(
                    variant: parts[0], selection: NSRange(location: l, length: n))
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                try? "{\"text\": \"\(escaped)\"}".write(
                    toFile: parts[2], atomically: true, encoding: .utf8)
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
                // The font at the start tells whether Markdown styling was
                // applied: "# título" opens 24 pt bold in Markdown, 14 pt
                // regular in honest plain text.
                let font = self.document.textStorage.length > 0
                    ? self.document.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    : nil
                let json = "{\"displayName\": \"\(self.document.displayName ?? "")\", " +
                    "\"fileURL\": \"\(self.document.fileURL?.path ?? "")\", " +
                    "\"formatName\": \"\(self.document.format.displayName)\", " +
                    "\"isMarkdown\": \(self.document.format.isMarkdown), " +
                    "\"supportsMarkdown\": \(self.document.format.supportsMarkdown), " +
                    "\"fontAtStart\": \"\(font.map { "\($0.fontName) \($0.pointSize)" } ?? "none")\", " +
                    "\"subtitle\": \"\(self.view.window?.subtitle ?? "")\", " +
                    "\"countBar\": \"\(self.editorController.debugCountBarText)\", " +
                    "\"previewText\": \"\(self.previewController?.debugPreviewText ?? "(preview not shown)")\"}"
                try? json.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        // Dumps the accessibility naming of the own views (outline rows,
        // count bar, preview, editor, full-window badge) plus the last
        // mode-change announcement and the key-view loop — lets automated
        // checks assert the VoiceOver wiring (v0.7.0) without VoiceOver.
        // Pair with -MarcusDebugShowPreview / -MarcusDebugShowOutline /
        // -MarcusShowWordCount to populate the views first.
        if let path = UserDefaults.standard.string(forKey: "MarcusDebugDumpA11y"),
           !debugA11yDumpScheduled {
            debugA11yDumpScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.dumpAccessibility(to: path)
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
    private var debugA11yDumpScheduled = false
    private var debugScriptApplied = false
    private var fileURLObservation: NSKeyValueObservation?

    // MARK: - Lazy panes

    /// The preview pane, created and attached on first show. Always the
    /// last pane: outline | editor | preview.
    @discardableResult
    private func ensurePreview() -> PreviewViewController {
        if let existing = previewController { return existing }
        let controller = PreviewViewController()
        let item = NSSplitViewItem(viewController: controller)
        item.minimumThickness = 280
        item.canCollapse = true
        item.isCollapsed = true
        addSplitViewItem(item)
        controller.apply(background: EditorTheme.current.palette.background)
        previewController = controller
        previewItem = item
        return controller
    }

    /// The outline pane, created and attached on first show. Always the
    /// first pane.
    @discardableResult
    private func ensureOutline() -> OutlineViewController {
        if let existing = outlineController { return existing }
        let controller = OutlineViewController()
        let item = NSSplitViewItem(viewController: controller)
        item.minimumThickness = 160
        item.maximumThickness = 320
        item.canCollapse = true
        item.isCollapsed = true
        insertSplitViewItem(item, at: 0)
        controller.onSelect = { [weak self] item in
            self?.editorController.goTo(range: item.range)
        }
        outlineController = controller
        outlineItem = item
        return controller
    }

    // MARK: - Toggle

    @objc func togglePreview(_ sender: Any?) {
        previewVisible.toggle()
        if previewVisible { ensurePreview() }
        applyPreviewLayout()
        if previewVisible { scheduleRender(afterDelay: 0) }
        // The layout shift is silent to VoiceOver; say what changed.
        announce(previewVisible ? L("Preview shown") : L("Preview hidden"))
    }

    /// Latest VoiceOver announcement, for `-MarcusDebugDumpA11y`.
    private(set) var lastAccessibilityAnnouncement = ""

    /// Posts a VoiceOver announcement for a mode change. High priority so it
    /// survives the user's own navigation; posted to the window (VoiceOver
    /// routes app-wide announcements through the key window).
    private func announce(_ message: String) {
        lastAccessibilityAnnouncement = message
        guard let window = view.window else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func applyPreviewLayout() {
        guard let previewItem else { return }  // preview never shown yet
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
        previewController?.setModeBadge(visible: showing,
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
            previewController?.apply(background: theme.palette.background)
            if previewVisible { scheduleRender(afterDelay: 0) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePreview(_:)) {
            menuItem.title = previewVisible ? L("Hide Preview") : L("Show Preview")
        }
        if menuItem.action == #selector(toggleOutline(_:)) {
            menuItem.title = outlineVisible ? L("Hide Outline") : L("Show Outline")
            // The outline reads Markdown headings; a .conf's "# comment"
            // lines are not sections (Fase 6).
            return document.format.supportsMarkdown
        }
        return true
    }

    // MARK: - Outline

    @objc func toggleOutline(_ sender: Any?) {
        outlineVisible.toggle()
        if outlineVisible { ensureOutline() }
        outlineItem?.animator().isCollapsed = !outlineVisible
        if outlineVisible { refreshOutline() }
        announce(outlineVisible ? L("Outline shown") : L("Outline hidden"))
    }

    /// Derives the outline from the highlighter's scan — already fresh after
    /// every edit, so nothing is re-parsed here.
    private func refreshOutline() {
        guard let outlineController else { return }
        // Belt and braces: the menu item is disabled for non-Markdown, but
        // the sidebar may already be open when Save As flips the format.
        guard document.format.supportsMarkdown else {
            outlineController.show([])
            return
        }
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
        previewController?.scroll(toCharacterLocation: location)
    }

    // MARK: - Accessibility verification hook

    /// Writes the own views' VoiceOver naming as JSON for `-MarcusDebugDumpA11y`.
    private func dumpAccessibility(to path: String) {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
        }
        func array(_ items: [String]) -> String {
            items.map { "\"\(esc($0))\"" }.joined(separator: ", ")
        }
        let json = "{" +
            "\"editorLabel\": \"\(esc(editorController.debugEditorA11yLabel))\", " +
            "\"countBarLabel\": \"\(esc(editorController.debugCountBarA11yLabel))\", " +
            "\"previewLabel\": \"\(esc(previewController?.debugPreviewA11yLabel ?? "(no preview)"))\", " +
            "\"badgeLabel\": \"\(esc(previewController?.debugBadgeA11yLabel ?? "(no preview)"))\", " +
            "\"outlineTableLabel\": \"\(esc(outlineController?.debugTableA11yLabel ?? "(no outline)"))\", " +
            "\"outlineRows\": [\(array(outlineController?.debugRowA11yLabels ?? []))], " +
            "\"lastAnnouncement\": \"\(esc(lastAccessibilityAnnouncement))\", " +
            "\"firstResponder\": \"\(esc(firstResponderLabel()))\", " +
            "\"dynamicTypeScale\": \(DynamicType.scale), " +
            "\"previewFontAtStart\": \(previewController?.debugFirstFontSize ?? 0), " +
            "\"paneOrder\": [\(array(paneOrderLabels()))]}"
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The split's arranged panes in visual (leading→trailing) order. This is
    /// the order VoiceOver walks the panes and the logical focus order the
    /// v0.7.0 scope asks for: outline → editor → preview.
    private func paneOrderLabels() -> [String] {
        // Each arranged subview is an _NSSplitViewItemViewWrapper; the
        // controller's view lives inside it, so match by descent, not identity.
        splitView.arrangedSubviews.map { sub in
            if outlineController?.view.isDescendant(of: sub) == true { return "outline" }
            if editorController?.view.isDescendant(of: sub) == true { return "editor" }
            if previewController?.view.isDescendant(of: sub) == true { return "preview" }
            return String(describing: type(of: sub))
        }
    }

    /// Where keyboard focus initially lands (the editor, so the user can type
    /// at once) — for the same hook.
    private func firstResponderLabel() -> String {
        guard let responder = view.window?.firstResponder as? NSView else { return "none" }
        return responder.accessibilityLabel()?.isEmpty == false
            ? responder.accessibilityLabel()!
            : String(describing: type(of: responder))
    }

    // MARK: - Rendering pipeline

    private func honestPreviewMessage() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = String(
            format: L("This format (%@) has no preview. Marcus is a primary tool for text, optimized for Markdown."),
            document.format.displayName
        )
        return NSAttributedString(string: "\n\n" + text, attributes: [
            .font: NSFont.systemFont(ofSize: DynamicType.scaled(13)),
            .foregroundColor: EditorTheme.current.palette.preview.secondaryText,
            .paragraphStyle: paragraph,
        ])
    }

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
        // Honest preview (Fase 6): the plain-text formats get a message,
        // not a render that would pretend the file is Markdown.
        guard document.format.supportsMarkdown else {
            previewController?.show(honestPreviewMessage())
            lastAnchors = []
            return
        }
        let text = document.textStorage.string
        let options = PreviewRenderOptions(
            baseURL: document.fileURL?.deletingLastPathComponent(),
            palette: EditorTheme.current.palette.preview,
            // Captured on the main thread; the render runs off it (Dynamic
            // Type, v0.7.0).
            fontScale: DynamicType.scale
        )
        Task.detached(priority: .userInitiated) {
            let rendered = MarkdownPreviewRenderer.render(text, options: options)
            await MainActor.run { [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.previewController?.show(rendered.string)
                self.lastAnchors = rendered.anchors
            }
        }
    }
}
