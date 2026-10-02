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
    /// Called once on the main thread when the job ends, with whether it
    /// produced output (Share as PDF waits for the file before offering it).
    var completion: ((Bool) -> Void)?

    init(destination: Destination, printInfo: NSPrintInfo, window: NSWindow?) {
        self.destination = destination
        self.printInfo = printInfo.copy() as! NSPrintInfo
        self.window = window
    }

    /// Blocks every network scheme the layout engine could otherwise reach
    /// (a remote `<img>` in raw HTML, a tracking pixel in a downloaded
    /// note). Local images arrive inlined as data URIs, which this does not
    /// touch, so the printed page matches the preview: Marcus never fetches
    /// anything from the network (D7).
    /// One rule per scheme: WebKit's url-filter dialect has no disjunction.
    private static let offlineRules: String = {
        let rules = ["http", "https", "ws", "wss", "ftp", "ftps"].map {
            "{\"trigger\": {\"url-filter\": \"^\($0)://\"}, \"action\": {\"type\": \"block\"}}"
        }
        return "[" + rules.joined(separator: ", ") + "]"
    }()

    func run(html: String) {
        retainedSelf = self
        // Compiling is quick and WebKit caches it by identifier; done per
        // job so the printer stays free of global state.
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "marcus-print-offline",
            encodedContentRuleList: Self.offlineRules
        ) { [weak self] list, _ in
            // WebKit may call back off the main thread: hop explicitly.
            nonisolated(unsafe) let rules = list
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.load(html: html, blocking: rules)
                }
            }
        }
    }

    private func load(html: String, blocking rules: WKContentRuleList?) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false  // D7
        if let rules {
            configuration.userContentController.add(rules)
        }
        let webView = WKWebView(
            frame: NSRect(origin: .zero, size: printInfo.paperSize),
            configuration: configuration
        )
        // Paper is white regardless of the app's appearance.
        webView.appearance = NSAppearance(named: .aqua)
        webView.navigationDelegate = self
        self.webView = webView
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
            let success = operation.run()
            finish(success: success)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    /// AppKit may invoke this off the main thread (observed when the job
    /// runs without a panel, writing a PDF): hop before touching state.
    @objc private nonisolated func printOperationDidRun(
        _ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        nonisolated(unsafe) let printer = self
        DispatchQueue.main.async {
            MainActor.assumeIsolated { printer.finish(success: success) }
        }
    }

    private func finish(success: Bool = false) {
        webView?.navigationDelegate = nil
        webView = nil
        retainedSelf = nil
        let completion = self.completion
        self.completion = nil
        completion?(success)
    }
}
