import Foundation

/// Egy kripto- vagy wallet-exportból felismert, csak olvasható pozíció.
///
/// Az értéket a fájl tartalmazza HUF-ban az export időpontjában. Nem kérünk
/// privát kulcsot, nem írunk láncra és nem indítunk vételt/eladást; amíg nincs
/// megbízható árfolyamforrás, az importált érték marad a mérés.
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

    init(id: String, platform: String, symbol: String, name: String,
         quantity: Decimal? = nil, currentValueHUF: Decimal,
         investedValueHUF: Decimal? = nil, unitPriceHUF: Decimal? = nil,
         asOf: Date? = nil, source: String) {
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
    }
}
