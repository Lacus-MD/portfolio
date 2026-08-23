import Foundation

/// EUR→HUF árfolyam.
///
/// Forrás az ECB napi referencia-árfolyama a Frankfurter API-n keresztül.
/// Az MNB SOAP-végpontja pontosabb lenne adóügyi szempontból, de CSAK
/// HTTP-n él (a HTTPS 404-et ad), az iOS ATS pedig tiltja a titkosítatlan
/// forgalmat. A két jegyzés eltérése 0,02% (365,03 vs 365,10) — értékkövetéshez
/// jelentéktelen, ezért nem nyitunk ATS-kivételt érte.
actor FXService {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    private struct Latest: Decodable {
        let date: String
        let rates: [String: Decimal]
    }

    /// Egy árfolyam-pillanatkép a forrás megjelölésével. A dátum azért kell,
    /// mert az ECB napi jegyzést ad délután — délelőtt a „legfrissebb" ECB-adat
    /// még a tegnapi, és ez fél százalékos eltérést okozhat a bróker élő
    /// értékeléséhez képest. Ha nem írjuk ki, ez néma hiba.
    struct Snapshot: Sendable {
        var eurHUF: Decimal
        var usdHUF: Decimal?
        var date: Date
        var source: String
    }

    private struct OpenER: Decodable {
        let result: String
        let time_last_update_unix: Double
        let rates: [String: Decimal]
    }

    private struct Series: Decodable {
        let rates: [String: [String: Decimal]]
    }

    /// A legutolsó EUR/HUF jegyzés (visszafelé kompatibilis alak).
    func currentRate() async throws -> Decimal {
        try await current().eurHUF
    }

    /// Elsődlegesen napra kész jegyzést kérünk; ha nem megy, marad az ECB.
    func current() async throws -> Snapshot {
        if let snapshot = try? await openERSnapshot() { return snapshot }
        return try await ecbSnapshot()
    }

    private func openERSnapshot() async throws -> Snapshot {
        let url = URL(string: "https://open.er-api.com/v6/latest/EUR")!
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(OpenER.self, from: data)
        guard decoded.result == "success", let huf = decoded.rates["HUF"], huf > 0 else {
            throw QuoteError.noData("EURHUF")
        }
        let usd = decoded.rates["USD"]
        return Snapshot(
            eurHUF: huf,
            usdHUF: (usd.map { $0 > 0 ? huf / $0 : nil } ?? nil),
            date: Date(timeIntervalSince1970: decoded.time_last_update_unix),
            source: "napi piaci"
        )
    }

    private func ecbSnapshot() async throws -> Snapshot {
        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=EUR&symbols=HUF,USD")!
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(Latest.self, from: data)
        guard let huf = decoded.rates["HUF"] else { throw QuoteError.noData("EURHUF") }
        let usd = decoded.rates["USD"]
        return Snapshot(
            eurHUF: huf,
            usdHUF: (usd.map { $0 > 0 ? huf / $0 : nil } ?? nil),
            date: Self.dayFormatter.date(from: decoded.date) ?? Date(),
            source: "ECB"
        )
    }

    /// Napi EUR/HUF idősor — a visszatöltéshez és a forintos bekerülési
    /// értékhez, hogy a múlt a KORABELI árfolyammal számoljon, ne a maival.
    func rates(from: Date, to: Date) async throws -> [Date: Decimal] {
        try await series(from: from, to: to, symbol: "HUF")
    }

    /// Napi USD/HUF idősor. Az ECB mindent euróhoz jegyez, ezért keresztárfolyam:
    /// USD/HUF = (EUR/HUF) / (EUR/USD).
    func usdRates(from: Date, to: Date) async throws -> [Date: Decimal] {
        let f = Self.dayFormatter
        let url = URL(string: "https://api.frankfurter.dev/v1/\(f.string(from: from))..\(f.string(from: to))?base=EUR&symbols=HUF,USD")!
        let (data, _) = try await session.data(from: url)
        let series = try JSONDecoder().decode(Series.self, from: data)

        var out: [Date: Decimal] = [:]
        for (key, value) in series.rates {
            guard let day = f.date(from: key),
                  let huf = value["HUF"], let usd = value["USD"], usd > 0 else { continue }
            out[Calendar.current.startOfDay(for: day)] = huf / usd
        }
        return out
    }

    private func series(from: Date, to: Date, symbol: String) async throws -> [Date: Decimal] {
        let f = Self.dayFormatter
        let url = URL(string: "https://api.frankfurter.dev/v1/\(f.string(from: from))..\(f.string(from: to))?base=EUR&symbols=\(symbol)")!
        let (data, _) = try await session.data(from: url)
        let series = try JSONDecoder().decode(Series.self, from: data)

        var out: [Date: Decimal] = [:]
        for (key, value) in series.rates {
            guard let day = f.date(from: key), let rate = value[symbol] else { continue }
            out[Calendar.current.startOfDay(for: day)] = rate
        }
        return out
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
