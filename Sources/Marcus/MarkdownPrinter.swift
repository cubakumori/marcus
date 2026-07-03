import AppKit
import MarcusPreview
import WebKit

/// Prints the document or saves it as a paginated PDF. The HTML comes from
/// the same exporter as Export as HTML; a WKWebView is created **on demand**
/// purely as a layout engine — JavaScript disabled, never on the editing
/// path, released as soon as the job ends (ROADMAP D7).
@MainActor
final class MarkdownPrinter: NSObject, WKNavigationDelegate {

    enum Destination {
        /// Standard print panel (which also offers Save as PDF).
        case printPanel
        /// Paginated PDF written to this URL without further UI.
        case pdfFile(URL)
    }

    private let destination: Destination
    private let printInfo: NSPrintInfo
    private weak var window: NSWindow?
    private var webView: WKWebView?
    /// Keeps the printer (and its web view) alive until the job ends.
    private var retainedSelf: MarkdownPrinter?

    init(destination: Destination, printInfo: NSPrintInfo, window: NSWindow?) {
        self.destination = destination
        self.printInfo = printInfo.copy() as! NSPrintInfo
        self.window = window
    }

    func run(html: String) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false  // D7
        let webView = WKWebView(
            frame: NSRect(origin: .zero, size: printInfo.paperSize),
            configuration: configuration
        )
        // Paper is white regardless of the app's appearance.
        webView.appearance = NSAppearance(named: .aqua)
        webView.navigationDelegate = self
        self.webView = webView
        retainedSelf = self
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let showsPanel: Bool
        switch destination {
        case .printPanel:
            showsPanel = true
        case .pdfFile(let url):
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
            showsPanel = false
        }

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = showsPanel
        operation.showsProgressPanel = false
        // WKWebView's print view starts with a zero frame; without this the
        // output comes out blank.
        operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)

        if let window {
            operation.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        } else {
            operation.run()
            finish()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    @objc private func printOperationDidRun(
        _ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        finish()
    }

    private func finish() {
        webView?.navigationDelegate = nil
        webView = nil
        retainedSelf = nil
    }
}
