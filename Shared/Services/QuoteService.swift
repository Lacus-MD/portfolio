import Foundation

struct Quote: Sendable {
    let isin: String
    let price: Decimal
    let changePercent: Double
    let timestamp: Date
}

enum QuoteError: LocalizedError {
    case noData(String)
    var errorDescription: String? {
        switch self {
        case .noData(let isin): "Nem érkezett árfolyam erre: \(isin)"
        }
    }
}

/// Árfolyam-lekérés ISIN alapján.
///
/// Elsődleges: Börse Frankfurt (Xetra) — kulcs nélkül, ISIN-alapú, és a
/// 2026-08-20-i ellenőrzésen mind a hét vizsgált Vanguard UCITS ETF-re adott
/// friss árat. Tartalék: Yahoo, ticker alapján — az működik, de rate-limitel
/// (429), ezért nem ez az elsődleges.
actor QuoteService {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    private static let browserUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    func quote(isin: String, ticker: String) async throws -> Quote {
        if let q = try? await frankfurtQuote(isin: isin) { return q }
        if let q = try? await yahooQuote(isin: isin, ticker: ticker) { return q }
        throw QuoteError.noData(isin)
    }

    // MARK: - Börse Frankfurt

    private struct FrankfurtQuote: Decodable {
        let lastPrice: Decimal?
        let changeToPrevDayInPercent: Double?
        let timestampLastPrice: String?
    }

    private func frankfurtQuote(isin: String) async throws -> Quote {
        var comps = URLComponents(string: "https://api.boerse-frankfurt.de/v1/data/quote_box/single")!
        comps.queryItems = [
            .init(name: "isin", value: isin),
            .init(name: "mic", value: "XETR"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw QuoteError.noData(isin) }
        let decoded = try JSONDecoder().decode(FrankfurtQuote.self, from: data)
        guard let price = decoded.lastPrice, price > 0 else { throw QuoteError.noData(isin) }

        return Quote(
            isin: isin,
            price: price,
            changePercent: decoded.changeToPrevDayInPercent ?? 0,
            timestamp: decoded.timestampLastPrice.flatMap(Self.iso.date(from:)) ?? Date()
        )
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Yahoo (tartalék + visszatöltés)

    private struct YahooChart: Decodable {
        struct Result: Decodable {
            struct Meta: Decodable {
                let regularMarketPrice: Decimal?
                let previousClose: Decimal?
            }
            let meta: Meta
            let timestamp: [Int]?
            struct Indicators: Decodable {
                struct Q: Decodable { let close: [Decimal?]? }
                let quote: [Q]?
            }
            let indicators: Indicators?
        }
        struct Chart: Decodable { let result: [Result]? }
        let chart: Chart
    }

    private func yahooChart(symbol: String, range: String, interval: String) async throws -> YahooChart.Result {
        var comps = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        comps.queryItems = [.init(name: "range", value: range), .init(name: "interval", value: interval)]
        var req = URLRequest(url: comps.url!)
        req.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw QuoteError.noData(symbol) }
        guard let result = try JSONDecoder().decode(YahooChart.self, from: data).chart.result?.first else {
            throw QuoteError.noData(symbol)
        }
        return result
    }

    private func yahooQuote(isin: String, ticker: String) async throws -> Quote {
        let result = try await yahooChart(symbol: "\(ticker).DE", range: "5d", interval: "1d")
        guard let price = result.meta.regularMarketPrice else { throw QuoteError.noData(ticker) }
        let prev = result.meta.previousClose ?? price
        let change = prev > 0 ? ((price - prev) / prev).doubleValue * 100 : 0
        return Quote(isin: isin, price: price, changePercent: change, timestamp: Date())
    }

    /// Napi záróárak visszamenőleg — a görbe visszatöltéséhez.
    /// Csak Yahoo tudja; ha rate-limitel, a hívó szépen elengedi.
    func dailyCloses(ticker: String, range: String) async throws -> [(Date, Decimal)] {
        try await dailyCloses(symbol: "\(ticker).DE", range: range)
    }

    /// Napi záróárak egy TELJES tőzsdei jelre (pl. „ABEA.DE").
    ///
    /// A `dailyCloses(ticker:)` a saját alapjainkhoz készült, és magától
    /// hozzáfűzi a `.DE`-t. A komponenseknél viszont a jel nem a tickerből
    /// képződik: az Alphabet Xetrán `ABEA.DE`, a Broadcom `1YD.DE`. Ezeket
    /// a `FundComposition` tárolja, ellenőrzött formában.
    func dailyCloses(symbol: String, range: String) async throws -> [(Date, Decimal)] {
        let result = try await yahooChart(symbol: symbol, range: range, interval: "1d")
        guard let stamps = result.timestamp,
              let closes = result.indicators?.quote?.first?.close else { return [] }
        return zip(stamps, closes).compactMap { stamp, close in
            guard let close, close > 0 else { return nil }
            return (Date(timeIntervalSince1970: TimeInterval(stamp)), close)
        }
    }
}

/// Egy kriptoeszköz CoinGecko-jegyzése forintban.
///
/// A Lightyear tranzakciós export a darabszámot és a bekerülési összeget
/// tartalmazza, aktuális piaci árat nem. Ez a külön modell azért kell, hogy a
/// piaci értéket frissíthessük anélkül, hogy a bekerülési adatot felülírnánk.
struct CryptoQuote: Sendable, Hashable {
    let symbol: String
    let coinID: String
    let priceHUF: Decimal
    let changePercent24h: Double?
    let timestamp: Date
    let source: String
}

enum CryptoQuoteError: LocalizedError {
    case noSymbols
    case unavailable
    case noData(String)

    var errorDescription: String? {
        switch self {
        case .noSymbols: "Nincs frissíthető kriptoeszköz."
        case .unavailable: "A CoinGecko árfolyamszolgáltatása nem érhető el."
        case .noData(let symbols): "Nem érkezett árfolyam erre: \(symbols)"
        }
    }
}

/// CoinGecko Simple Price kliens.
///
/// A REST végpont több eszközt egyetlen kérésben ad vissza, ezért egy
/// frissítési kör nem indít külön hálózati kérést minden tokenhez. Az app csak
/// olvas: nincs kereskedési vagy számla-hozzáférés, API-kulcsot sem tárolunk a
/// kliensben.
actor CryptoQuoteService {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private static let endpoint = "https://api.coingecko.com/api/v3/simple/price"

    /// A Lightyear és a gyakori wallet-exportok szimbólumaihoz tartozó
    /// CoinGecko azonosítók. A szimbólum alapján nem kérünk találgató keresést:
    /// így pl. a több, azonos tickerű token nem keverhető össze.
    static let coinIDs: [String: String] = [
        "BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana", "UNI": "uniswap",
        "XRP": "ripple", "ADA": "cardano", "DOT": "polkadot", "AVAX": "avalanche-2",
        "LINK": "chainlink", "LTC": "litecoin", "BCH": "bitcoin-cash", "DOGE": "dogecoin",
        "SHIB": "shiba-inu", "MATIC": "matic-network", "POL": "polygon-ecosystem-token",
        "ATOM": "cosmos", "AAVE": "aave", "ALGO": "algorand", "XLM": "stellar",
        "NEAR": "near", "FIL": "filecoin", "TRX": "tron", "SAND": "the-sandbox",
        "MANA": "decentraland", "USDT": "tether", "USDC": "usd-coin", "DAI": "dai",
        "OP": "optimism", "ARB": "arbitrum"
    ]

    private struct Price: Decodable {
        let huf: Decimal?
        let huf24hChange: Double?
        let lastUpdatedAt: Int?

        enum CodingKeys: String, CodingKey {
            case huf
            case huf24hChange = "huf_24h_change"
            case lastUpdatedAt = "last_updated_at"
        }
    }

    /// Lekéri az összes ismert szimbólum árát egyetlen CoinGecko-kérésben.
    /// Ismeretlen vagy átmenetileg kimaradó tokenekhez nem gyártunk nullás
    /// árat: a hívó ilyenkor megtartja az utolsó ismert értéket.
    func quotes(for symbols: [String]) async throws -> [String: CryptoQuote] {
        let normalized = Array(Set(symbols.map { $0.uppercased() })).sorted()
        let requests = normalized.compactMap { symbol -> (String, String)? in
            guard let id = Self.coinIDs[symbol] else { return nil }
            return (symbol, id)
        }
        guard !requests.isEmpty else {
            if normalized.isEmpty { throw CryptoQuoteError.noSymbols }
            throw CryptoQuoteError.noData(normalized.joined(separator: ", "))
        }

        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "ids", value: requests.map { $0.1 }.joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "huf"),
            URLQueryItem(name: "include_24hr_change", value: "true"),
            URLQueryItem(name: "include_last_updated_at", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Portfolio/1.0 (read-only crypto quotes)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw CryptoQuoteError.unavailable
        }
        let decoded = try JSONDecoder().decode([String: Price].self, from: data)
        // A legacy ticker and its successor can occasionally share an API id.
        // Keep the first deterministic mapping instead of trapping on duplicate
        // dictionary keys; unsupported aliases simply keep their last value.
        let idToSymbol = requests.reduce(into: [String: String]()) { result, request in
            if result[request.1] == nil { result[request.1] = request.0 }
        }
        let result = decoded.compactMap { id, value -> (String, CryptoQuote)? in
            guard let symbol = idToSymbol[id], let huf = value.huf, huf > 0 else { return nil }
            let timestamp = value.lastUpdatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            return (symbol, CryptoQuote(symbol: symbol, coinID: id, priceHUF: huf,
                                        changePercent24h: value.huf24hChange,
                                        timestamp: timestamp, source: "CoinGecko"))
        }
        guard !result.isEmpty else {
            throw CryptoQuoteError.noData(requests.map { $0.0 }.joined(separator: ", "))
        }
        return Dictionary(uniqueKeysWithValues: result)
    }
}
