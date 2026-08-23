import Foundation

/// Egy alap belső összetétele — a legnagyobb tételek és a maradék.
///
/// **Beégetett pillanatkép, nem élő adat.** A Vanguardnak nincs nyilvános
/// API-ja (a `vanguardinvestor.co.uk` Angular HTML-vázat ad vissza), az
/// összetétel pedig havonta frissül. Ezért dátummal együtt tároljuk, és a
/// felület kiírja, mikori.
struct FundComposition: Codable, Hashable {
    struct Slice: Codable, Hashable, Identifiable {
        var id: String { name }
        let name: String
        let weightPct: Double
        /// A Xetrán jegyzett ISIN, ha van — ezen kérhető le a napi mozgás.
        /// A TSMC ADR-je például nincs ott, ezért nála nil.
        var isin: String?
        /// Amire a hírkereső rákeres.
        var searchTerm: String?
        /// Az amerikai ticker — a dizájn a név alatt mutatja.
        var ticker: String?
        /// A Xetra-jel a Yahoo-nál, EUR-ban jegyezve — ebből jön a TÖRTÉNETI
        /// árfolyam. Mindegyiket a Yahoo saját cégneve alapján ellenőriztem
        /// (`chart/<jel>` → `meta.longName`), nem tippelés: az `MTE.DE`
        /// tényleg a Micron, az `1YD.DE` tényleg a Broadcom.
        /// A TSMC-nek nincs Xetra-jegyzése, ott marad a napi gyűjtés.
        var xetra: String?
    }

    let isin: String
    let asOf: String
    let totalHoldings: Int
    let top: [Slice]

    /// A top-10-en kívüli rész — ez teszi őszintévé az ábrát.
    var restPct: Double { max(0, 100 - top.reduce(0) { $0 + $1.weightPct }) }

    /// A 2026-08-21-én justETF-ről ellenőrzött összetétel.
    static let known: [String: FundComposition] = [
        "IE00BK5BQT80": FundComposition(
            isin: "IE00BK5BQT80",
            asOf: "2026. aug.",
            totalHoldings: 3757,
            top: [
                .init(name: "NVIDIA", weightPct: 4.45, isin: "US67066G1040", searchTerm: "NVIDIA stock", ticker: "NVDA", xetra: "NVD.DE"),
                .init(name: "Apple", weightPct: 3.98, isin: "US0378331005", searchTerm: "Apple stock", ticker: "AAPL", xetra: "APC.DE"),
                .init(name: "Microsoft", weightPct: 2.64, isin: "US5949181045", searchTerm: "Microsoft stock", ticker: "MSFT", xetra: "MSF.DE"),
                .init(name: "Amazon", weightPct: 2.20, isin: "US0231351067", searchTerm: "Amazon stock", ticker: "AMZN", xetra: "AMZ.DE"),
                .init(name: "Alphabet A", weightPct: 1.99, isin: "US02079K3059", searchTerm: "Alphabet Google stock", ticker: "GOOGL", xetra: "ABEA.DE"),
                .init(name: "TSMC", weightPct: 1.75, isin: nil, searchTerm: "TSMC stock", ticker: "TSM"),
                .init(name: "Broadcom", weightPct: 1.67, isin: "US11135F1012", searchTerm: "Broadcom stock", ticker: "AVGO", xetra: "1YD.DE"),
                .init(name: "Alphabet C", weightPct: 1.60, isin: nil, searchTerm: nil, ticker: "GOOG", xetra: "ABEC.DE"),
                .init(name: "Micron", weightPct: 1.24, isin: "US5951121038", searchTerm: "Micron stock", ticker: "MU", xetra: "MTE.DE"),
                .init(name: "Meta", weightPct: 1.18, isin: "US30303M1027", searchTerm: "Meta Platforms stock", ticker: "META", xetra: "FB2A.DE"),
            ]
        )
    ]
}
