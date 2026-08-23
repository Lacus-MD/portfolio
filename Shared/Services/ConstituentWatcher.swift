import Foundation

/// Egy nagyot mozdult komponens és a hozzá tartozó hír.
struct ConstituentMove: Identifiable, Hashable {
    var id: String { name }
    let name: String
    /// Aktuális ár a Xetrán, euróban.
    var price: Decimal = 0
    let changePct: Double
    /// Súlya az alapban — ez tartja meg az arányérzéket.
    let weightPct: Double
    var headline: String?
    var link: String?
    /// ISIN, hogy a részletnézet külön is le tudjon kérni adatot.
    var isin: String?
    /// A Xetra-jel — ebből tölti be a részletnézet a történeti görbét.
    var xetra: String?
    /// Az amerikai ticker (AAPL, NVDA) — a kártya a név alatt mutatja.
    var ticker: String?
    /// Az app által gyűjtött napi záróárak — a szikragörbéhez.
    var history: [Double] = []

    /// Mennyivel mozdítja az ALAPOT ez a komponens. Ez az igazi szám:
    /// egy 5%-os esés 4,5%-os súllyal 0,2 százalékpont az alapon.
    var contributionPct: Double { changePct * weightPct / 100 }
}

/// Figyeli az alap legnagyobb komponenseit, és csak akkor keres hírt,
/// ha valamelyik **nagyot mozdult**.
///
/// Miért esemény-vezérelt: egy 3 757 papírból álló világindexnél a napi
/// komponens-hírfolyam zaj. Az viszont érdekes, ha valami kiugrót esett vagy
/// emelkedett — akkor van mit megérteni. A küszöb alatt egyáltalán nem
/// hálózunk hírért.
actor ConstituentWatcher {

    private let quotes = QuoteService()
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    /// MINDEN követhető komponens napi mozgása, hatás szerint rendezve.
    ///
    /// A hírlekérés továbbra is esemény-vezérelt: csak a `newsThreshold` fölött
    /// mozdultakhoz kérünk címet. A napi mozgás viszont mindig látszik — a
    /// „hogyan alakulnak a részvények" kérdésre ez a válasz, és ehhez nem kell
    /// hírt hálózni.
    func snapshot(of composition: FundComposition,
                  newsThreshold: Double = 3,
                  newsLimit: Int = 3) async -> [ConstituentMove] {
        var found: [ConstituentMove] = []

        // A ma mért árakat elmentjük, hogy a görbe napról napra épüljön.
        var payload = PortfolioFile.load()
        let today = Self.dayKey(Date())

        for slice in composition.top {
            guard let isin = slice.isin else { continue }
            guard let quote = try? await quotes.quote(isin: isin, ticker: slice.name) else { continue }

            payload.constituentPrices[isin, default: [:]][today] = quote.price
            let history = payload.constituentPrices[isin]?
                .sorted { $0.key < $1.key }
                .suffix(60)
                .map { $0.value.doubleValue } ?? []

            found.append(ConstituentMove(name: slice.name,
                                         price: quote.price,
                                         changePct: quote.changePercent,
                                         weightPct: slice.weightPct,
                                         isin: isin,
                                         xetra: slice.xetra,
                                         ticker: slice.ticker,
                                         history: history))
        }
        // Csak akkor írunk, ha volt mit mérni — üres kör ne nyúljon a fájlhoz.
        if !found.isEmpty { PortfolioFile.save(payload) }

        // A legnagyobb HATÁSÚ elsőként — nem a legnagyobb százalék, hanem
        // amelyik a súlyával együtt tényleg mozdít az alapon.
        found.sort { abs($0.contributionPct) > abs($1.contributionPct) }

        // Hírt csak a kiugrókhoz, és legfeljebb néhányhoz — különben minden
        // megnyitás tíz hálózati kérés lenne a semmiért.
        var asked = 0
        for index in found.indices where asked < newsLimit {
            guard abs(found[index].changePct) >= newsThreshold else { continue }
            guard let term = composition.top.first(where: { $0.name == found[index].name })?.searchTerm
            else { continue }
            if let item = await headline(for: term) {
                found[index].headline = item.title
                found[index].link = item.link
            }
            asked += 1
        }
        return found
    }

    /// Nap-kulcs a tároláshoz. Sztring, nem `Date`: így a JSON-szótár kulcsa
    /// stabil és emberi szemmel is olvasható marad.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func headline(for term: String) async -> (title: String, link: String)? {
        var comps = URLComponents(string: "https://news.google.com/rss/search")!
        comps.queryItems = [
            .init(name: "q", value: term),
            .init(name: "hl", value: "en-US"),
            .init(name: "gl", value: "US"),
            .init(name: "ceid", value: "US:en"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await session.data(from: url),
              let xml = String(data: data, encoding: .utf8) else { return nil }

        // Az első <item> a legfrissebb; a csatorna saját <title>-jét kihagyjuk.
        guard let block = xml.components(separatedBy: "<item").dropFirst().first else { return nil }
        func field(_ tag: String) -> String? {
            guard let open = block.range(of: "<\(tag)>"),
                  let close = block.range(of: "</\(tag)>", range: open.upperBound..<block.endIndex)
            else { return nil }
            let raw = String(block[open.upperBound..<close.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return HTMLEntities.decode(raw)
        }
        guard let title = field("title"), let link = field("link") else { return nil }
        return (title, link)
    }
}
