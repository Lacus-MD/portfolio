import SwiftUI
import SafariServices

/// Cikkolvasó az appon belül — **szöveg, nem weboldal**.
///
/// A cikk törzsét az `ArticleExtractor` szedi ki a kész DOM-ból, és itt
/// natívan rajzoljuk ki: a téma betűivel, a téma színeivel, olvasható
/// sorhosszal. Se hirdetés, se süti-sáv, se elcsúszó elrendezés.
///
/// Ha a kiolvasás nem megy — akadnak lapok, ahol a törzsszöveg fizetőfal
/// mögött van vagy csak görgetésre töltődik —, azt KIMONDJUK, és felkínáljuk
/// a böngészőt. Csendben félig üres oldalt mutatni rosszabb volna.
struct NewsReader: View {
    let item: NewsItem
    @Environment(\.dismiss) private var dismiss
    @State private var extractor = ArticleExtractor()
    @State private var showBrowser = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let article = extractor.article {
                        body(of: article)
                    } else if extractor.failed {
                        failure
                    } else {
                        loading
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
                .readableWidth(620)
            }
            .background(DS.Color.canvas)
            .foregroundStyle(DS.Color.ink)
            .navigationTitle(item.source)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vissza") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if let url = URL(string: item.link) {
                            ShareLink("Megosztás", item: url)
                            Button("Megnyitás a böngészőben") { showBrowser = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showBrowser) {
                if let url = URL(string: item.link) { SafariView(url: url) }
            }
        }
        .tint(DS.Color.coral)
        .task {
            guard let url = URL(string: item.link) else { return }
            extractor.load(url)
        }
    }

    // MARK: - Részek

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(DS.font(23, .semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(item.source)
                if let byline = extractor.article?.byline { Text("· \(byline)") }
                if let date = item.date { Text("· \(Fmt.time(date))") }
                if item.language != "hu" { Text("· angolul") }
            }
            .font(DS.meta)
            .foregroundStyle(DS.Color.inkSoft(0.5))
            Rectangle().fill(DS.Color.inkSoft(0.12)).frame(height: 1)
        }
    }

    private func body(of article: Article) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, text in
                if text.hasPrefix("## ") {
                    Text(text.dropFirst(3))
                        .font(DS.font(17, .semibold))
                        .padding(.top, 6)
                } else {
                    Text(text)
                        .font(DS.font(16, .regular))
                        .lineSpacing(6)
                        .foregroundStyle(DS.Color.inkSoft(0.88))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Lélegző helyőrző — ugyanaz a nyelv, mint a lista betöltésénél.
    private var loading: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(0..<5, id: \.self) { index in
                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(width: nil, height: 12, delay: Double(index) * 0.12)
                    SkeletonBar(width: nil, height: 12, delay: Double(index) * 0.12 + 0.04)
                    SkeletonBar(width: 190, height: 12, delay: Double(index) * 0.12 + 0.08)
                }
            }
        }
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ennek a cikknek a szövegét nem sikerült kiolvasni")
                .font(DS.font(15, .medium))
            Text("Van, ahol a törzsszöveg fizetőfal mögött van, vagy csak a böngészőben épül fel. A címet és a forrást fent látod — az egész cikk a böngészőben olvasható.")
                .font(DS.meta)
                .foregroundStyle(DS.Color.inkSoft(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button { showBrowser = true } label: {
                Label("Megnyitás a böngészőben", systemImage: "safari")
                    .font(DS.button)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .pastelCardBackground(in: Capsule(), opacity: 0.55)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }
}

/// Tartalék: az eredeti oldal, ha a szöveges kiolvasás nem megy.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: config)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A megjelenített hírek kiszolgálóihoz előre felépíti a kapcsolatot.
/// Hivatalos API — nem tölt le tartalmat, csak DNS-t és TLS-t intéz el előre.
enum NewsPrewarmer {
    private static var token: SFSafariViewController.PrewarmingToken?

    static func prewarm(_ items: [NewsItem]) {
        let urls = items.compactMap { URL(string: $0.link) }
        guard !urls.isEmpty else { return }
        token?.invalidate()
        token = SFSafariViewController.prewarmConnections(to: Array(urls.prefix(8)))
    }
}
