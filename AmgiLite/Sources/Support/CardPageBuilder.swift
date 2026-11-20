import AmgiCardWeb
import AnkiKit

enum CardSide {
    case front
    case back
}

/// Assembles the page the review screen loads. Kept deliberately smaller than
/// the main app's `CardHTMLBuilder` (no typed-answer, TTS or dictionary bridge
/// yet); what matters here is the Anki contract: notetype CSS, the
/// `amgi-asset://media/` base, and the `nightMode` class templates key off.
enum CardPageBuilder {
    static func page(for card: RenderedCard, side: CardSide, isDark: Bool) -> String {
        let bodyHTML = side == .front ? card.frontHTML : card.backHTML
        let bodyClass = isDark ? "card nightMode" : "card"
        let htmlClass = isDark ? "nightMode" : ""
        let textColor = isDark ? "#f2f2f2" : "#1a1a1a"
        let linkColor = isDark ? "#8fb8ff" : "#2f6f5e"

        return """
        <!doctype html>
        <html class="\(htmlClass)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <meta name="color-scheme" content="\(isDark ? "dark" : "light")">
        <base href="\(CardAssetPath.mediaBaseURL.absoluteString)">
        <style>
        :root { color-scheme: \(isDark ? "dark" : "light"); }
        html, body { margin: 0; padding: 0; background: transparent; }
        body {
            font: -apple-system-body;
            font-size: 17px;
            line-height: 1.45;
            color: \(textColor);
            padding: 16px;
            -webkit-text-size-adjust: 100%;
            word-wrap: break-word;
            overflow-wrap: anywhere;
        }
        a { color: \(linkColor); }
        img, video, audio { max-width: 100%; height: auto; }
        table { max-width: 100%; }
        pre, code { white-space: pre-wrap; }
        \(card.cardCSS)
        </style>
        </head>
        <body class="\(bodyClass)">
        \(bodyHTML)
        </body>
        </html>
        """
    }
}
