import AmgiCardWeb
import UIKit
import WebKit

/// The card surface the review screen renders into. `CardViewHosting` is the
/// seam: Phase 2's review view controller only knows the protocol.
final class CardWebView: UIView, CardViewHosting {
    private let webView: WKWebView
    private let schemeHandler: CardSchemeHandler

    var isLoading: Bool { webView.isLoading }

    init(mediaRootProvider: @escaping () -> URL?) {
        let configuration = WKWebViewConfiguration()
        let handler = CardSchemeHandler(mediaRootProvider: mediaRootProvider)
        configuration.setURLSchemeHandler(handler, forURLScheme: CardAssetPath.scheme)

        self.schemeHandler = handler
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: .zero)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func load(html: String, baseURL: URL?) {
        webView.loadHTMLString(html, baseURL: baseURL ?? CardAssetPath.cardBaseURL)
    }
}
