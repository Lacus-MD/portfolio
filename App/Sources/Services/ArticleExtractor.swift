import SwiftUI
import WebKit

/// Egy cikk kiolvasott, SZÖVEGES tartalma.
struct Article: Equatable {
    var title: String
    var byline: String?
    var paragraphs: [String]
    /// Igaz, ha a kiolvasás lefutott, de nem talált érdemi szöveget.
    var isEmpty: Bool { paragraphs.isEmpty }
}

/// Cikk szövegének kinyerése — „olvasó mód".
///
/// **Miért rejtett `WKWebView` és nem HTML-elemzés Swiftben:** a hírportálok
/// oldala nem statikus. A Google News hivatkozásai átirányítanak, több lap
/// JavaScriptből tölti a törzsszöveget, a jelölés pedig oldalanként más.
/// Egy reguláris kifejezéses elemző ezeken sorra elbukna. A böngészőmotor
/// viszont a KÉSZ DOM-ot adja, amiből a szöveg kiszedése már egyszerű —
/// és a felhasználó ebből semmit nem lát, mert a nézet sosem jelenik meg:
/// csak a kiolvasott bekezdéseket rajzoljuk ki natívan.
@MainActor
@Observable
final class ArticleExtractor: NSObject {

    private(set) var article: Article?
    private(set) var failed = false
    private var webView: WKWebView?
    private var finished = false

    /// A kiolvasó szkript.
    ///
    /// Nem külső könyvtár: a pontszámozás annyi, hogy megkeressük azt a
    /// SZÜLŐELEMET, amely alatt a legtöbb bekezdés-szöveg van, és annak a
    /// bekezdéseit adjuk vissza. A sallangot (menü, lábléc, hirdetés,
    /// ajánló) előbb kivágjuk, mert különben ezek szövege felhízlalná a
    /// pontszámot.
    private static let script = """
    (function () {
      try {
        var junk = 'script,style,noscript,svg,form,nav,header,footer,aside,iframe,' +
          'figcaption,[aria-hidden="true"],[class*="advert"],[class*="promo"],' +
          '[class*="newsletter"],[class*="related"],[class*="share"],[class*="social"],' +
          '[class*="comment"],[id*="comment"],[class*="cookie"],[class*="consent"],' +
          '[class*="subscribe"],[class*="paywall"],[class*="recirc"]';
        document.querySelectorAll(junk).forEach(function (n) { n.remove(); });

        var blocks = Array.prototype.slice.call(document.querySelectorAll('p, h2, h3'));
        var scores = new Map();
        blocks.forEach(function (el) {
          var text = (el.innerText || '').trim();
          if (el.tagName === 'P' && text.length < 45) { return; }
          var parent = el.parentElement;
          if (!parent) { return; }
          scores.set(parent, (scores.get(parent) || 0) + text.length);
        });

        var best = null, bestScore = 0;
        scores.forEach(function (value, key) {
          if (value > bestScore) { bestScore = value; best = key; }
        });
        if (!best || bestScore < 220) { return null; }

        var out = [];
        Array.prototype.slice.call(best.children).forEach(function (el) {
          if (['P', 'H2', 'H3', 'LI'].indexOf(el.tagName) < 0) { return; }
          var text = (el.innerText || '').replace(/\\s+/g, ' ').trim();
          if (text.length < 2) { return; }
          if (el.tagName !== 'P' && text.length > 140) { return; }
          out.push((el.tagName === 'P' || el.tagName === 'LI') ? text : '## ' + text);
        });

        function meta(sel, attr) {
          var el = document.querySelector(sel);
          return el ? (el.getAttribute(attr) || '') : '';
        }
        return JSON.stringify({
          title: meta('meta[property="og:title"]', 'content') || document.title || '',
          byline: meta('meta[name="author"]', 'content'),
          paragraphs: out
        });
      } catch (e) { return null; }
    })()
    """

    func load(_ url: URL) {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        // Nulla méret: a nézet sosem kerül a képernyőre, csak dolgozik.
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: url))

        // Van, hogy a `didFinish` sosem jön el (végtelen betöltés, követő
        // szkriptek). Egy határidő után azzal dolgozunk, ami addig megvan.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            self?.extract(reason: .timeout)
        }
    }

    private enum Reason { case finished, timeout }

    private func extract(reason: Reason) {
        guard !finished, let view = webView else { return }
        view.evaluateJavaScript(Self.script) { [weak self] result, _ in
            guard let self else { return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawArticle.self, from: data),
                  !raw.paragraphs.isEmpty
            else {
                // Időzítőre még nem adjuk fel: hátha a betöltés befejeződik.
                if reason == .finished { self.finished = true; self.failed = true }
                return
            }
            self.finished = true
            self.article = Article(title: raw.title,
                                   byline: raw.byline?.isEmpty == false ? raw.byline : nil,
                                   paragraphs: raw.paragraphs)
            self.webView = nil
        }
    }

    private struct RawArticle: Decodable {
        var title: String
        var byline: String?
        var paragraphs: [String]
    }
}

extension ArticleExtractor: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Rövid türelem: a törzsszöveget több lap a `load` UTÁN teszi be.
            try? await Task.sleep(for: .milliseconds(700))
            self.extract(reason: .finished)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.failed = true }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.failed = true }
    }
}
