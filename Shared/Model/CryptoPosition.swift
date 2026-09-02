import Foundation

/// Egy kripto- vagy wallet-exportból felismert, csak olvasható pozíció.
///
/// Az importált bekerülési és mennyiségi adat mellé opcionális, olvasott piaci
/// jegyzés társul. Nem kérünk privát kulcsot, nem írunk láncra és nem indítunk
/// vételt/eladást.
struct CryptoPosition: Identifiable, Codable, Hashable {
    let id: String
    var platform: String
    var symbol: String
    var name: String
    var quantity: Decimal?
    var currentValueHUF: Decimal
    var investedValueHUF: Decimal?
    var unitPriceHUF: Decimal?
    var asOf: Date?
    var source: String
    /// Aktuális CoinGecko-jegyzésből számolt egységár. Az importált
    /// `unitPriceHUF` a bekerülési egységár marad, hogy a hozam számítása ne
    /// veszítse el a viszonyítási alapját.
    var marketPriceHUF: Decimal?
    /// CoinGecko 24 órás változása százalékban.
    var marketChangePercent: Double?
    /// A piaci jegyzés időpontja (Unix timestampből).
    var marketAsOf: Date?
    /// Az árfolyam forrása, jelenleg CoinGecko.
    var marketSource: String?

    init(id: String, platform: String, symbol: String, name: String,
         quantity: Decimal? = nil, currentValueHUF: Decimal,
         investedValueHUF: Decimal? = nil, unitPriceHUF: Decimal? = nil,
         asOf: Date? = nil, source: String,
         marketPriceHUF: Decimal? = nil,
         marketChangePercent: Double? = nil,
         marketAsOf: Date? = nil,
         marketSource: String? = nil) {
        self.id = id
        self.platform = platform
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.currentValueHUF = currentValueHUF
        self.investedValueHUF = investedValueHUF
        self.unitPriceHUF = unitPriceHUF
        self.asOf = asOf
        self.source = source
        self.marketPriceHUF = marketPriceHUF
        self.marketChangePercent = marketChangePercent
        self.marketAsOf = marketAsOf
        self.marketSource = marketSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        platform = try c.decodeIfPresent(String.self, forKey: .platform) ?? "crypto"
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "CRYPTO"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? symbol
        quantity = try c.decodeIfPresent(Decimal.self, forKey: .quantity)
        currentValueHUF = try c.decodeIfPresent(Decimal.self, forKey: .currentValueHUF) ?? 0
        investedValueHUF = try c.decodeIfPresent(Decimal.self, forKey: .investedValueHUF)
        unitPriceHUF = try c.decodeIfPresent(Decimal.self, forKey: .unitPriceHUF)
        asOf = try c.decodeIfPresent(Date.self, forKey: .asOf)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "Kripto-export"
        marketPriceHUF = try c.decodeIfPresent(Decimal.self, forKey: .marketPriceHUF)
        marketChangePercent = try c.decodeIfPresent(Double.self, forKey: .marketChangePercent)
        marketAsOf = try c.decodeIfPresent(Date.self, forKey: .marketAsOf)
        marketSource = try c.decodeIfPresent(String.self, forKey: .marketSource)
    }
}
