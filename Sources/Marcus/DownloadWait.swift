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
///
/// The panel never becomes the key window: it is information, not a
/// dialog, and taking key would make AppKit hand key back to the previous
/// tab when it closes — right after the new document's tab was selected
/// (observed in Ernesto's round, 2026-10-05). It stays up until the
/// document is open and goes away with `dismiss()`.
@MainActor
final class DownloadWait {

    /// One entry per wait, for -MarcusDebugDumpDocState: file name,
    /// milliseconds until the bytes arrived (or the user gave up), message
    /// shown, and whether it was cancelled.
    static var debugWaits: [(name: String, milliseconds: Double, message: String, cancelled: Bool)] = []

    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private var onCancel: (() -> Void)?

    /// Calls `proceed(true)` once the file has its data (immediately when
    /// it already has), `proceed(false)` if the user cancels the wait. The
    /// panel stays visible after `proceed(true)` until `dismiss()`.
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
            if !ok { self?.dismiss() }
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

    /// Takes the panel down; the controller calls it once the document is
    /// on screen (or at once when the user cancelled).
    func dismiss() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        onCancel = nil
    }

    private func show(message: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 120),
            styleMask: [.titled],
            backing: .buffered, defer: false)
        panel.title = "Marcus"
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let content = NSView()
        panel.contentView = content

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        let title = NSTextField(wrappingLabelWithString: message)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        title.preferredMaxLayoutWidth = 360
        let detail = NSTextField(wrappingLabelWithString: L("Marcus will open it as soon as it has arrived."))
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.preferredMaxLayoutWidth = 360

        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancelPressed(_:)))
        cancel.bezelStyle = .rounded

        for view in [spinner, title, detail, cancel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        // Alert-like: spinner at the left, texts to its right, the button
        // at the bottom right under the texts.
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            spinner.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            spinner.widthAnchor.constraint(equalToConstant: 32),
            spinner.heightAnchor.constraint(equalToConstant: 32),

            title.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),

            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cancel.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 16),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 460, height: content.fittingSize.height))
        panel.setAccessibilityLabel(message)
        panel.center()
        // Shown, not made key: see the type comment.
        panel.orderFront(nil)
        self.panel = panel

        // Escape cancels even though the panel is not key.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.panel != nil else { return event }
            MainActor.assumeIsolated { self?.onCancel?() }
            return nil
        }

        // -MarcusDebugSnapshotDownloadPanel /o.png: the panel as drawn.
        if let path = UserDefaults.standard.string(forKey: "MarcusDebugSnapshotDownloadPanel") {
            content.layoutSubtreeIfNeeded()
            if let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    @objc private func cancelPressed(_ sender: Any?) {
        onCancel?()
    }
}
