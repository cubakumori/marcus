import AppKit
import MarcusPreview

/// Editor on the left, optional preview on the right. The preview costs
/// nothing while hidden: no parsing, no rendering (manifesto: the editing
/// path never waits).
final class DocumentSplitViewController: NSSplitViewController, NSMenuItemValidation {

    private let document: MarkdownDocument
    private let previewController = PreviewViewController()
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    private var previewVisible = false

    private var renderGeneration = 0
    private var debounce: DispatchWorkItem?

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

        editorItem = NSSplitViewItem(viewController: EditorViewController(document: document))
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
        return true
    }

    // MARK: - Rendering pipeline

    @objc private func storageDidChange(_ notification: Notification) {
        scheduleRender(afterDelay: 0.3)
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
