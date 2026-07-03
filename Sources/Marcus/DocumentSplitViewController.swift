import AppKit
import MarcusPreview

/// Editor on the left, optional preview on the right. The preview costs
/// nothing while hidden: no parsing, no rendering (manifesto: the editing
/// path never waits).
final class DocumentSplitViewController: NSSplitViewController, NSMenuItemValidation {

    private let document: MarkdownDocument
    private let previewController = PreviewViewController()
    private var previewItem: NSSplitViewItem!

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

        let editorItem = NSSplitViewItem(viewController: EditorViewController(document: document))
        editorItem.minimumThickness = 320
        addSplitViewItem(editorItem)

        previewItem = NSSplitViewItem(viewController: previewController)
        previewItem.minimumThickness = 280
        previewItem.canCollapse = true
        previewItem.isCollapsed = true
        addSplitViewItem(previewItem)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidChange(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: document.textStorage
        )
    }

    // MARK: - Toggle

    @objc func togglePreview(_ sender: Any?) {
        previewItem.animator().isCollapsed.toggle()
        if !previewItem.isCollapsed { scheduleRender(afterDelay: 0) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePreview(_:)) {
            menuItem.title = previewItem.isCollapsed ? "Show Preview" : "Hide Preview"
        }
        return true
    }

    // MARK: - Rendering pipeline

    @objc private func storageDidChange(_ notification: Notification) {
        scheduleRender(afterDelay: 0.3)
    }

    private func scheduleRender(afterDelay delay: TimeInterval) {
        guard !previewItem.isCollapsed else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.startRender() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startRender() {
        renderGeneration += 1
        let generation = renderGeneration
        let text = document.textStorage.string
        let options = PreviewRenderOptions(baseURL: document.fileURL?.deletingLastPathComponent())
        Task.detached(priority: .userInitiated) {
            let rendered = MarkdownPreviewRenderer.render(text, options: options)
            await MainActor.run { [weak self] in
                guard let self, generation == self.renderGeneration else { return }
                self.previewController.show(rendered.string)
            }
        }
    }
}
