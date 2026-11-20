import Foundation
import WebKit
import AmgiCardWeb

/// Serves `amgi-asset://media/...` and `amgi-asset://assets/...` for the card
/// web view. Rewritten from `AmgiFeatures/ReviewFeature/CardAssetScheme.swift`
/// without `AnkiClients`/`Dependencies`: the media root comes from a closure
/// over `CollectionServicing.mediaFolderPath`.
final class CardSchemeHandler: NSObject, WKURLSchemeHandler {
    private let mediaRootProvider: () -> URL?
    private var activeTasks: Set<ObjectIdentifier> = []

    init(mediaRootProvider: @escaping () -> URL?) {
        self.mediaRootProvider = mediaRootProvider
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let key = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(key)

        let mediaRoot = mediaRootProvider()
        let bundleRoot = Bundle.main.resourceURL

        if url.host?.lowercased() == "media", mediaRoot == nil {
            finish(key: key) {
                self.respond(to: urlSchemeTask, url: url, statusCode: 503, mimeType: "text/plain", data: Data())
            }
            return
        }

        guard let fileURL = CardAssetPath.resolve(url: url, mediaRoot: mediaRoot, bundleRoot: bundleRoot) else {
            // `amgi-asset://card/...` is only a base URL for relative links; it
            // never maps to a file, so 204 rather than a 404 in the console.
            finish(key: key) {
                self.respond(to: urlSchemeTask, url: url, statusCode: 204, mimeType: "text/plain", data: Data())
            }
            return
        }

        let mimeType = CardAssetPath.mimeType(for: fileURL)
        // Reading on the scheme-handler thread blocks the renderer for every
        // image/audio file on the card; the read hops to a background queue and
        // the reply returns to main.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe)
            DispatchQueue.main.async {
                guard let self else { return }
                self.finish(key: key) {
                    if let data {
                        self.respond(to: urlSchemeTask, url: url, statusCode: 200, mimeType: mimeType, data: data)
                    } else {
                        self.respond(to: urlSchemeTask, url: url, statusCode: 404, mimeType: "text/plain", data: Data())
                    }
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // WebKit raises an uncatchable exception if a stopped task is answered.
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    private func finish(key: ObjectIdentifier, _ body: () -> Void) {
        guard activeTasks.contains(key) else { return }
        activeTasks.remove(key)
        body()
    }

    private func respond(
        to task: any WKURLSchemeTask,
        url: URL,
        statusCode: Int,
        mimeType: String,
        data: Data
    ) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
            ]
        ) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }

        task.didReceive(response)
        if !data.isEmpty {
            task.didReceive(data)
        }
        task.didFinish()
    }
}
