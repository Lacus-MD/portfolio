import Foundation

/// Egy WebKincstár exportból felismert állampapír-sor.
///
/// Ez szándékosan nem `Holding`: az állampapírnak nincs ugyanaz a tőzsdei
/// árfolyam- és darabszám-modellje, mint egy ETF-nek. A részletes exportadatot
/// mégis megőrizzük, hogy a lejárati naptár és az egyeztetés ne csak az
/// összesített egyenleget lássa.
struct StateTreasuryPosition: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var isin: String?
    var nominalValue: Decimal?
    var currentValueHUF: Decimal
    var investedValueHUF: Decimal?
    var maturityDate: Date?
    var couponPct: Decimal?
    var asOf: Date?

    init(id: String, name: String, isin: String? = nil,
         nominalValue: Decimal? = nil, currentValueHUF: Decimal,
         investedValueHUF: Decimal? = nil, maturityDate: Date? = nil,
         couponPct: Decimal? = nil, asOf: Date? = nil) {
        self.id = id
        self.name = name
        self.isin = isin
        self.nominalValue = nominalValue
        self.currentValueHUF = currentValueHUF
        self.investedValueHUF = investedValueHUF
        self.maturityDate = maturityDate
        self.couponPct = couponPct
        self.asOf = asOf
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Állampapír"
        isin = try c.decodeIfPresent(String.self, forKey: .isin)
        nominalValue = try c.decodeIfPresent(Decimal.self, forKey: .nominalValue)
        currentValueHUF = try c.decodeIfPresent(Decimal.self, forKey: .currentValueHUF) ?? 0
        investedValueHUF = try c.decodeIfPresent(Decimal.self, forKey: .investedValueHUF)
        maturityDate = try c.decodeIfPresent(Date.self, forKey: .maturityDate)
        couponPct = try c.decodeIfPresent(Decimal.self, forKey: .couponPct)
        asOf = try c.decodeIfPresent(Date.self, forKey: .asOf)
    }
}
