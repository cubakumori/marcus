import AppKit
import MarcusCore

/// «Descargando de iCloud…» (hallazgo de Ernesto, 2026-10-05): a file in
/// iCloud Drive that "Optimize Mac Storage" has evicted is *dataless*, and
/// NSDocument's coordinated read then waits silently — 25 s for 4 KB — while
/// the user stares at the previous window. Before opening such a file the
/// document controller shows this small panel, asks the system to fetch
/// the bytes, and opens the document the moment they are on disk. Any
/// File Provider is covered (the dataless flag is the system's, not
/// iCloud's); the wording names iCloud only when the file really is there.
@MainActor
final class DownloadWait {

    /// One entry per wait, for -MarcusDebugDumpDocState: file name,
    /// milliseconds until the bytes arrived (or the user gave up), message
    /// shown, and whether it was cancelled.
    static var debugWaits: [(name: String, milliseconds: Double, message: String, cancelled: Bool)] = []

    private var panel: NSPanel?
    private var onCancel: (() -> Void)?

    /// Calls `proceed(true)` once the file has its data (immediately when
    /// it already has), `proceed(false)` if the user cancels the wait.
    func run(for url: URL, proceed: @escaping @MainActor (Bool) -> Void) {
        guard CloudFile.isDataless(url) else {
            proceed(true)
            return
        }
        let name = url.lastPathComponent
        let inCloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem ?? false
        let message = inCloud
            ? String(format: L("Downloading “%@” from iCloud…"), name)
            : String(format: L("Downloading “%@”…"), name)
        let started = Date()
        var finished = false
        let finish: @MainActor (Bool) -> Void = { [weak self] ok in
            guard !finished else { return }
            finished = true
            Self.debugWaits.append((name, Date().timeIntervalSince(started) * 1000, message, !ok))
            self?.close()
            proceed(ok)
        }
        onCancel = { finish(false) }
        show(message: message)

        // iCloud takes a hint; every provider materializes on the first
        // read, which blocks — off the main thread — until the bytes exist.
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let path = url.path
        Task.detached(priority: .userInitiated) {
            if let handle = FileHandle(forReadingAtPath: path) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
            }
            await MainActor.run { finish(true) }
        }
    }

    private func show(message: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 110),
            styleMask: [.titled],
            backing: .buffered, defer: false)
        panel.title = "Marcus"
        panel.isReleasedWhenClosed = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let title = NSTextField(wrappingLabelWithString: message)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let detail = NSTextField(wrappingLabelWithString: L("Marcus will open it as soon as it has arrived."))
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPressed(_:)))
        cancel.keyEquivalent = "\u{1b}"

        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 4
        let row = NSStackView(views: [spinner, texts])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        let content = NSStackView(views: [row, cancel])
        content.orientation = .vertical
        content.alignment = .trailing
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content
        NSLayoutConstraint.activate([content.widthAnchor.constraint(equalToConstant: 440)])
        panel.setAccessibilityLabel(message)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    @objc private func cancelPressed(_ sender: Any?) {
        onCancel?()
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
        onCancel = nil
    }
}
