import Foundation

struct Quote {
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
