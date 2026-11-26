#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

/// Hosts the Smart Size Chart embed page in a `WKWebView`, presented as a sheet.
///
/// Create a fresh controller for every presentation: after a close the page is blank.
///
/// ```swift
/// let vc = SSCSizeChartViewController(product: product, callbacks: SSCCallbacks(
///     onSelectSize: { event in select(event.sizeId) },
///     onAddToCart: { event in addToCart(event.sizeId) }
/// ))
/// vc.present(from: self)
/// ```
public final class SSCSizeChartViewController: UIViewController {
    public weak var delegate: SSCDelegate?
    public var callbacks: SSCCallbacks

    public private(set) var product: SSCProduct
    public let config: SSCConfig?
    public let anonId: String?
    /// The URL loaded, nil when the SDK is not configured.
    public let embedURL: URL?

    /// Set by the SwiftUI wrapper so a page-initiated dismissal updates its binding.
    var dismissHandler: (() -> Void)?

    private var webView: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .large)
    private var loadTimer: Timer?
    private var hasLoaded = false
    private var didReportClose = false
    private var didReloadAfterCrash = false
    private var embedOrigin: (scheme: String?, host: String?, port: Int?)

    /// - Parameters:
    ///   - config: Overrides the config set with `SSC.configure(_:)`.
    public init(
        product: SSCProduct,
        config: SSCConfig? = nil,
        delegate: SSCDelegate? = nil,
        callbacks: SSCCallbacks = SSCCallbacks()
    ) {
        self.product = product
        self.config = config ?? SSC.config
        self.delegate = delegate
        self.callbacks = callbacks
        if let resolved = self.config {
            let id = SSCAnonID.resolve(hostId: resolved.anonId)
            anonId = id
            embedURL = SSCEmbedURL.build(config: resolved, productId: product.id, anonId: id)
            let base = resolved.environment.embedURL
            embedOrigin = (base.scheme?.lowercased(), base.host?.lowercased(), base.port)
        } else {
            anonId = nil
            embedURL = nil
            embedOrigin = (nil, nil, nil)
        }
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        loadTimer?.invalidate()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
    }

    /// Presents the sheet. On iPad it shows as a form sheet.
    public func present(from presenter: UIViewController, animated: Bool = true) {
        presenter.present(self, animated: animated)
    }

    // MARK: - Inbound API

    /// Switches the open sheet to another product (`BoldMetricsEmbed.setProduct`).
    public func setProduct(_ product: SSCProduct) {
        self.product = product
        guard let json = try? SSCInjectedObject(product: product, locale: config?.locale).jsonString() else { return }
        hasLoaded = false
        evaluate("(function(o){window.BoldMetricsEmbed&&window.BoldMetricsEmbed.setProduct(o.product.id,o.product);})(\(json));")
    }

    /// Asks the page to close (same path as its X). The sheet dismisses on `bmi_close`.
    public func close() {
        evaluate("window.BoldMetricsEmbed&&window.BoldMetricsEmbed.close();")
    }

    // MARK: - View

    static let handlerName = "boldmetrics"

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let contentController = WKUserContentController()
        contentController.add(WeakMessageHandler(self), name: Self.handlerName)
        if config?.productDelivery == .userScript,
           let json = try? SSCInjectedObject(product: product, locale: config?.locale).jsonString() {
            contentController.addUserScript(WKUserScript(
                source: "window._boldmetrics = \(json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        let configuration = WKWebViewConfiguration()
        // Default (persistent) store, so saved answers survive between opens.
        configuration.websiteDataStore = .default()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) { webView.isInspectable = config?.debug ?? false }
        view.addSubview(webView)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        guard let config, let embedURL else {
            report(.notConfigured)
            return
        }
        spinner.startAnimating()
        loadTimer = Timer.scheduledTimer(withTimeInterval: config.loadTimeout, repeats: false) { [weak self] _ in
            guard let self, !self.hasLoaded else { return }
            self.report(.timeout)
            self.dismissSheet()
        }
        webView.load(URLRequest(url: embedURL))
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingRemoved else { return }
        handleNativeDismissal()
    }

    /// True when this controller, or an ancestor (SwiftUI's hosting controller), is going away.
    private var isBeingRemoved: Bool {
        var vc: UIViewController? = self
        while let current = vc {
            if current.isBeingDismissed || current.isMovingFromParent { return true }
            vc = current.parent
        }
        return presentingViewController == nil
    }

    /// The shopper swiped the sheet down (or the host dismissed it). Ask the page to close so
    /// close telemetry is sent, keep the web view alive briefly, report one close.
    private func handleNativeDismissal() {
        loadTimer?.invalidate()
        guard !didReportClose else { return }
        if hasLoaded {
            let retained = webView
            webView?.evaluateJavaScript("window.BoldMetricsEmbed&&window.BoldMetricsEmbed.close();")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = retained }
        }
        reportClose()
    }

    private func dismissSheet() {
        loadTimer?.invalidate()
        if let dismissHandler {
            dismissHandler()
        } else if presentingViewController != nil {
            dismiss(animated: true)
        }
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script) { _, error in
            if let error { NSLog("BoldMetricsSSC: script failed: \(error.localizedDescription)") }
        }
    }

    // MARK: - Bridge

    func handle(_ message: SSCMessage) {
        let event = SSCEvent(message)
        delegate?.sscDidReceive(event, message: message)
        callbacks.onEvent?(event, message)

        switch event {
        case .embedBoot:
            if config?.productDelivery == .bridge,
               let json = try? SSCInjectedObject(product: product, locale: config?.locale).jsonString() {
                evaluate("window.BoldMetricsEmbed&&window.BoldMetricsEmbed.init(\(json));")
            }
        case .loaded:
            hasLoaded = true
            loadTimer?.invalidate()
            spinner.stopAnimating()
            delegate?.sscDidLoad()
            callbacks.onLoad?()
        case .recommendation(let e):
            delegate?.sscDidRecommend(e)
            callbacks.onRecommendation?(e)
        case .selectedSize(let e):
            delegate?.sscDidSelectSize(e)
            callbacks.onSelectSize?(e)
        case .addToCart(let e):
            delegate?.sscDidAddToCart(e)
            callbacks.onAddToCart?(e)
        case .selectedItem(let item):
            delegate?.sscDidSelectItem(item)
            callbacks.onSelectedItem?(item)
        case .close:
            reportClose()
            dismissSheet()
        case .embedError(let code, let message):
            // Can come before or instead of bmi_ssc_loaded. The page shows the message;
            // the shopper can swipe the sheet away.
            loadTimer?.invalidate()
            spinner.stopAnimating()
            report(.embed(code: code, message: message))
        case .openURL(let url):
            openExternally(url)
        case .continueClicked, .formSubmission, .widgetError, .unknown:
            break
        }
    }

    private func report(_ error: SSCError) {
        spinner.stopAnimating()
        delegate?.sscDidFail(error)
        callbacks.onError?(error)
    }

    private func reportClose() {
        guard !didReportClose else { return }
        didReportClose = true
        delegate?.sscDidClose()
        callbacks.onClose?()
    }

    private func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }

    fileprivate func isEmbedOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == embedOrigin.scheme
            && url.host?.lowercased() == embedOrigin.host
            && url.port == embedOrigin.port
    }
}

// MARK: - WKNavigationDelegate, WKUIDelegate

extension SSCSizeChartViewController: WKNavigationDelegate, WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        // Sub-frames (none today) load what they like; the main frame stays on the embed origin.
        if navigationAction.targetFrame?.isMainFrame == false { return decisionHandler(.allow) }
        if url.scheme == "about" || isEmbedOrigin(url) { return decisionHandler(.allow) }
        openExternally(url)
        decisionHandler(.cancel)
    }

    // target=_blank links.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { openExternally(url) }
        return nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failLoad(error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failLoad(error)
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
            decisionHandler(.cancel)
            report(.loadFailed("HTTP \(http.statusCode)"))
            dismissSheet()
            return
        }
        decisionHandler(.allow)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !didReloadAfterCrash, let embedURL else {
            report(.loadFailed("Web content process terminated"))
            dismissSheet()
            return
        }
        didReloadAfterCrash = true
        hasLoaded = false
        spinner.startAnimating()
        webView.load(URLRequest(url: embedURL))
    }

    private func failLoad(_ error: Error) {
        let nsError = error as NSError
        // Our own cancellations (external links, policy cancels) aren't failures.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return } // frame load interrupted
        guard !hasLoaded else { return }
        report(.loadFailed(error.localizedDescription))
        dismissSheet()
    }
}

// MARK: - Message handler

/// `WKUserContentController` retains its handlers; this breaks the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: SSCSizeChartViewController?
    init(_ target: SSCSizeChartViewController) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let decoded = SSCMessage(body: message.body) else { return }
        target?.handle(decoded)
    }
}
#endif
