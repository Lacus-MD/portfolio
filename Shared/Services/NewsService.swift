import Foundation

/// Hírek magyar gazdasági RSS-ekből.
///
/// **Miért RSS és nem hír-API:** a Yahoo és társai kulcs nélkül rate-limitelnek
/// (a mérésben végig 429-et adtak). Az RSS ingyenes, kulcs nélküli, és stabil.
///
/// **Miért szűrünk:** a nyers hírfolyamban a „forint" legtöbbször csak pénznem
/// („50 ezer forintos támogatás"), nem árfolyam. A te portfóliódat két dolog
/// mozgatja — az EUR/HUF és a világpiac —, tehát csak arra szűrünk. Minden
/// tétel megmondja, miért került be.
actor NewsService {

    private struct Feed { let name: String; let url: String; let language: String }

    /// Magyar és angol források vegyesen. A magyarok a forintot fedik le (ez
    /// mozgat nálad a legnagyobbat), az angolok a világpiacot és az alap
    /// nagy tételeit — arról magyarul alig írnak.
    ///
    /// Mind ingyenes és kulcs nélküli; mind mérve 2026-08-22-én.
    /// A Yahoo hír-API kimaradt: tartósan 429-cel válaszol.
    private let feeds = [
        Feed(name: "Portfolio", url: "https://www.portfolio.hu/rss/all.xml", language: "hu"),
        Feed(name: "Index", url: "https://index.hu/gazdasag/rss/", language: "hu"),
        Feed(name: "VG", url: "https://www.vg.hu/feed", language: "hu"),
        Feed(name: "CNBC", url: "https://www.cnbc.com/id/100003114/device/rss/rss.html", language: "en"),
        Feed(name: "MarketWatch", url: "https://feeds.content.dowjones.io/public/rss/mw_topstories", language: "en"),
        Feed(name: "Investing", url: "https://www.investing.com/rss/news_25.rss", language: "en"),
        Feed(name: "Seeking Alpha", url: "https://seekingalpha.com/market_currents.xml", language: "en"),
    ]

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadRevalidatingCacheData
        return URLSession(configuration: c)
    }()

    /// A devizahatást magyarázó hírek: a „forint" csak akkor számít, ha
    /// árfolyam-szövegkörnyezetben áll.
    private let forintTerms = ["forint", "eur/huf", "euróárfolyam", "devizapiac"]
    private let forintContext = ["erősöd", "gyengül", "árfolyam", "euró", "jegybank",
                                 "mnb", "kamatdönt", "alapkamat", "leértékel", "felértékel"]
    private let marketTerms = ["tőzsde", "részvény", "s&p", "nasdaq", "wall street",
                               "index", "piac", "infláci", "fed", "ezb", "recesszi",
                               "kötvény", "hozam", "kamatvágás", "kamatemel", "gdp",
                               "chip", "mesterséges intelligenc", "olaj", "arany",
                               "dollár", "befektet", "etf",
                               // angol
                               "stocks", "market", "nasdaq", "dow", "s&p 500",
                               "inflation", "rate cut", "earnings", "treasury",
                               "bond", "recession", "tariff", "jobs report"]

    // Az alapod legnagyobb tételeit a `HoldingMatcher` ismeri fel — ott a
    // lista szóhatáros, és ott van a névhez rendelés is, hogy a hír a
    // megfelelő papír alá kerüljön.

    func fetch(limit: Int = 6) async -> [NewsItem] {
        var all: [NewsItem] = []
        for feed in feeds {
            guard let url = URL(string: feed.url) else { continue }
            guard let (data, _) = try? await session.data(from: url),
                  let xml = String(data: data, encoding: .utf8) else { continue }
            all.append(contentsOf: parse(xml, source: feed.name, language: feed.language))
        }

        // Azonos hír több lapon is megjelenhet — cím szerint deduplikálunk.
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.title.lowercased()).inserted }

        // Sorrend: konkrét tétel → forint → piac; azon belül a frissebb.
        func rank(_ r: NewsItem.Reason) -> Int {
            switch r { case .holding: 0; case .forint: 1; case .market: 2 }
        }
        return unique
            .sorted {
                if $0.reason != $1.reason { return rank($0.reason) < rank($1.reason) }
                return ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// A `<description>` egy soros kivonata. A csatornák HTML-t tesznek bele
    /// (kép, hivatkozás, „Tovább a cikkre"), ezért a jelölést kiszedjük.
    /// Ha a maradék a CÍMMEL kezdődik vagy túl rövid, nincs mit mutatni —
    /// egy megismételt cím nem összefoglaló.
    private func summary(from block: String, title: String) -> String? {
        guard let raw = extract("description", from: block) else { return nil }
        var text = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = HTMLEntities.decode(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 40, !text.lowercased().hasPrefix(title.lowercased().prefix(30))
        else { return nil }
        return text.count > 190 ? String(text.prefix(189)) + "…" : text
    }

    /// Vezető kép: `<enclosure url=…>` vagy `<media:content|thumbnail url=…>`.
    private func imageURL(from block: String) -> String? {
        for pattern in ["<enclosure[^>]+url=\"([^\"]+)\"",
                        "<media:content[^>]+url=\"([^\"]+)\"",
                        "<media:thumbnail[^>]+url=\"([^\"]+)\""] {
            if let range = block.range(of: pattern, options: .regularExpression) {
                let match = String(block[range])
                if let start = match.range(of: "url=\""),
                   let end = match.range(of: "\"", range: start.upperBound..<match.endIndex) {
                    let url = String(match[start.upperBound..<end.lowerBound])
                    if url.hasPrefix("http") { return url }
                }
            }
        }
        return nil
    }

    private func parse(_ xml: String, source: String, language: String) -> [NewsItem] {
        var items: [NewsItem] = []
        for block in xml.components(separatedBy: "<item").dropFirst() {
            guard let title = extract("title", from: block),
                  let link = extract("link", from: block) else { continue }
            guard let reason = relevance(of: title) else { continue }
            items.append(NewsItem(
                title: title, link: link, source: source,
                date: extract("pubDate", from: block).flatMap(Self.parseDate),
                language: language,
                reason: reason,
                summary: summary(from: block, title: title),
                imageURL: imageURL(from: block),
                holding: HoldingMatcher.match(title)
            ))
        }
        return items
    }

    /// Miért releváns — vagy egyáltalán az-e.
    private func relevance(of title: String) -> NewsItem.Reason? {
        let lower = title.lowercased()
        // Konkrét tétel a legfontosabb: arról szól, amit ténylegesen birtokolsz.
        if HoldingMatcher.containsAny(lower) { return .holding }
        if forintTerms.contains(where: lower.contains),
           forintContext.contains(where: lower.contains) {
            return .forint
        }
        if marketTerms.contains(where: lower.contains) { return .market }
        return nil
    }

    private func extract(_ tag: String, from block: String) -> String? {
        guard let open = block.range(of: "<\(tag)>"),
              let close = block.range(of: "</\(tag)>", range: open.upperBound..<block.endIndex)
        else { return nil }
        var value = String(block[open.upperBound..<close.lowerBound])
        value = value.replacingOccurrences(of: "<![CDATA[", with: "")
                     .replacingOccurrences(of: "]]>", with: "")
        return HTMLEntities.decode(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let rfc822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    private static func parseDate(_ text: String) -> Date? { rfc822.date(from: text) }
}
