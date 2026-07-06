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
    }

    private var debugPDFExported = false

    // MARK: - Toggle

    @objc func togglePreview(_ sender: Any?) {
        previewVisible.toggle()
        applyPreviewLayout()
        if previewVisible { scheduleRender(afterDelay: 0) }
    }

    private func applyPreviewLayout() {
        previewItem.animator().isCollapsed = !previewVisible
        // Full-window mode reads better without the editor beside it.
        editorItem.animator().isCollapsed = previewVisible && PreviewMode.current == .full
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
            }
        }
    }
}
