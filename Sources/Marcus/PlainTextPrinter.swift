import AppKit

/// Prints the honest plain-text formats (Fase 6, D15) — HTML, CSS, logs,
/// config files… — as what they are: monospaced text, lines wrapped at the
/// page width, black on white whatever the editor theme. No Markdown, no
/// WebKit: an off-screen NSTextView that AppKit paginates natively.
@MainActor
final class PlainTextPrinter: NSObject {

    /// 10 pt is the usual size for code on paper; the editor's own size and
    /// zoom are for the screen.
    static let fontSize: CGFloat = 10
    /// Tab stops every 4 characters, as code editors show them.
    static let tabWidth = 4

    private let operation: NSPrintOperation
    private weak var window: NSWindow?
    private var retainedSelf: PlainTextPrinter?
    var completion: ((Bool) -> Void)?

    init(text: String, title: String, destination: MarkdownPrinter.Destination,
         printInfo: NSPrintInfo, window: NSWindow?) {
        let info = printInfo.copy() as! NSPrintInfo
        // Same paper setup as the Markdown printer.
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        if case .pdfFile(let url) = destination {
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        }

        let view = Self.textView(for: text, width: info.paperSize.width - info.leftMargin - info.rightMargin)
        operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = { if case .printPanel = destination { return true } else { return false } }()
        operation.showsProgressPanel = false
        self.window = window
    }

    /// Exposed for the tests: the laid-out page content.
    static func textView(for text: String, width: CGFloat) -> NSTextView {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        let advance = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.tabStops = []
        paragraph.defaultTabInterval = advance * CGFloat(tabWidth)
        // Long lines (minified CSS, log lines) wrap anywhere rather than
        // only at spaces, so nothing runs off the page.
        paragraph.lineBreakMode = .byCharWrapping

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // Paper is white regardless of the app's appearance.
        textView.appearance = NSAppearance(named: .aqua)
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]))
        textView.sizeToFit()
        return textView
    }

    func run() {
        retainedSelf = self
        if let window {
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            finish(success: operation.run())
        }
    }

    /// AppKit may call this off the main thread (as with MarkdownPrinter).
    @objc private nonisolated func printOperationDidRun(
        _ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        let printer = self
        DispatchQueue.main.async {
            MainActor.assumeIsolated { printer.finish(success: success) }
        }
    }

    private func finish(success: Bool) {
        completion?(success)
        completion = nil
        retainedSelf = nil
    }
}
