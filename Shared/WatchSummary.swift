import Foundation

/// A telefon → óra adatszerződés.
///
/// Miért nem App Group: az óra **külön eszköz**, nem éri el a telefon
/// konténerét. A WatchConnectivity `applicationContext`-je viszont pontosan
/// erre való — kis, mindig a legfrissebb állapotot tartó csomag.
///
/// Szándékosan kicsi és számokra szűkített: az óra nem számol, csak megjelenít.
struct WatchSummary: Codable, Hashable {

    struct Row: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var monogram: String
        /// A platform akcentusa nyers néven, hogy az óra ne függjön a
        /// telefon enumjától, ha az egyik oldal frissül.
        var accent: String
        var valueHUF: Decimal
        var gainPct: Double
    }

    /// Egy lezárt időszak eredménye. Az óra nem számol — készen kapja.
    struct Period: Codable, Hashable, Identifiable {
        var id: Int
        var title: String
        var pct: Double
        var gainHUF: Decimal
    }

    var totalHUF: Decimal = 0
    var gainHUF: Decimal = 0
    var gainPct: Double = 0
    var rows: [Row] = []
    /// Utolsó **mérés** ideje a telefonon — az óra ebből tudja, mennyire friss.
    var asOf: Date?
    /// Legfeljebb 30 napi mérés a szikragörbéhez.
    var spark: [Double] = []
    /// Napi, heti, havi eredmény — annyi, amennyihez van korábbi mérés.
    var periods: [Period] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalHUF = try c.decodeIfPresent(Decimal.self, forKey: .totalHUF) ?? 0
        gainHUF  = try c.decodeIfPresent(Decimal.self, forKey: .gainHUF) ?? 0
        gainPct  = try c.decodeIfPresent(Double.self,  forKey: .gainPct) ?? 0
        rows     = try c.decodeIfPresent([Row].self,   forKey: .rows) ?? []
        asOf     = try c.decodeIfPresent(Date.self,    forKey: .asOf)
        spark    = try c.decodeIfPresent([Double].self, forKey: .spark) ?? []
        periods  = try c.decodeIfPresent([Period].self, forKey: .periods) ?? []
    }
}

/// Az óra oldalán tárolt utolsó állapot. Az óra offline is mutat valamit,
/// és megmondja, mennyire régi.
enum WatchStore {
    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appending(path: "watch-summary.json")
    }

    static func load() -> WatchSummary {
        guard let url, let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(WatchSummary.self, from: data)
        else { return WatchSummary() }
        return value
    }

    static func save(_ summary: WatchSummary) {
        guard let url, let data = try? JSONEncoder().encode(summary) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
