import UIKit

/// Phase 0 seam kept for the review screen: it renders card HTML and reports
/// when the page is still loading. `CardWebView` is the live implementation;
/// tests and previews can substitute a stub.
protocol CardViewHosting: AnyObject {
    func load(html: String, baseURL: URL?)
    var isLoading: Bool { get }
}
