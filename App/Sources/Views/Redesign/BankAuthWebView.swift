import SwiftUI
@preconcurrency import WebKit

/// A bank jóváhagyó oldala, saját ablakban — és a visszairányítás elkapása.
///
/// **Miért nem `ASWebAuthenticationSession`:** az egyedi séma (`portfolio://`)
/// lenne hozzá a természetes visszaút, csakhogy az Enable Banking regisztrációja
/// KIZÁRÓLAG `https` címet fogad el (mérve: „URL uses unsupported scheme").
/// Az `ASWebAuthenticationSession` https-visszaútja viszont univerzális
/// hivatkozást kíván, ahhoz pedig saját domain és azon elhelyezett
/// társítási fájl kellene — nekünk nincs.
///
/// Ezért a jóváhagyás egy beágyazott `WKWebView`-ban fut, és a
/// visszairányítást a navigáció ELŐTT fogjuk el: amint a cím a beállított
/// redirect URL-lel kezdődik, megállítjuk a betöltést és kivesszük a `code`
/// paramétert. A `https://localhost/eb-callback` így soha nem is töltődik be —
/// nem kell hozzá kiszolgáló.
struct BankAuthWebView: UIViewRepresentable {
    let url: URL
    let redirectPrefix: String
    let onResult: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Külön adattár: a banki munkamenet ne keveredjen a hírolvasóéval,
        // és a jóváhagyás után ne maradjon bejelentkezve.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: BankAuthWebView
        private var finished = false

        init(_ parent: BankAuthWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url,
                  target.absoluteString.hasPrefix(parent.redirectPrefix) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            guard !finished else { return }
            finished = true
            parent.onResult(.success(target))
        }

        /// A visszairányítás célja nem létezik (localhost), ezért a betöltés
        /// hibával zárulhat, MIELŐTT a fenti szabály lefutna. Ilyenkor a
        /// hibában lévő címből is kivesszük a kódot — a lényeg megvan.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            let failing = (error as NSError)
                .userInfo[NSURLErrorFailingURLStringErrorKey] as? String
            if let failing, failing.hasPrefix(parent.redirectPrefix),
               let url = URL(string: failing), !finished {
                finished = true
                parent.onResult(.success(url))
                return
            }
            guard !finished else { return }
            finished = true
            parent.onResult(.failure(error))
        }
    }
}

/// A jóváhagyó ablak kerete: cím, mégse gomb, és alatta a banki oldal.
struct BankAuthSheet: View {
    let url: URL
    let redirectPrefix: String
    let bankName: String
    let onResult: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BankAuthWebView(url: url, redirectPrefix: redirectPrefix) { result in
                onResult(result)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(bankName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") {
                        onResult(.failure(EnableBankingError.callback(
                            "A banki jóváhagyást megszakítottad.")))
                        dismiss()
                    }
                }
            }
        }
        .tint(DS.Color.coral)
    }
}
