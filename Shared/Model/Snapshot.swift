import Foundation

/// Egy napi pillanatkép a portfólió értékéről.
///
/// Szándékos tervezési döntés: a görbét az app MAGA építi napi mentésekből,
/// nem külső történeti API-ból. A portfólió alakulása ugyanis nem azonos az
/// ETF árfolyamával — a befizetések megtörik a görbét —, és a kipróbált
/// történeti végpontok (Börse Frankfurt price_history, Stooq) vagy üresek
/// vagy halottak voltak.
struct Snapshot: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// A nap kezdete (nap pontosságú kulcs, naponta egy rekord).
    var date: Date
    var valueEUR: Decimal
    var costEUR: Decimal
    /// EUR→HUF az adott napon (ECB napi referencia).
    var fxRate: Decimal
    /// Igaz, ha a sort a Yahoo-visszatöltés hozta létre, nem élő mérés.
    var isBackfilled: Bool = false
    /// Platformonkénti forintérték ugyanabban a mérésben. Enélkül az
    /// összehasonlító nézet nem tudna platformonként 100-ra indexálni —
    /// az összesített görbéből ez nem vezethető vissza.
    var byPlatform: [String: Decimal] = [:]

    init(id: UUID = UUID(), date: Date, valueEUR: Decimal, costEUR: Decimal,
         fxRate: Decimal, isBackfilled: Bool = false,
         byPlatform: [String: Decimal] = [:]) {
        self.id = id; self.date = date; self.valueEUR = valueEUR
        self.costEUR = costEUR; self.fxRate = fxRate; self.isBackfilled = isBackfilled
        self.byPlatform = byPlatform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(UUID.self,    forKey: .id) ?? UUID()
        date         = try c.decode(Date.self,             forKey: .date)
        valueEUR     = try c.decode(Decimal.self,          forKey: .valueEUR)
        costEUR      = try c.decodeIfPresent(Decimal.self, forKey: .costEUR) ?? 0
        fxRate       = try c.decodeIfPresent(Decimal.self, forKey: .fxRate) ?? 0
        isBackfilled = try c.decodeIfPresent(Bool.self,    forKey: .isBackfilled) ?? false
        byPlatform   = try c.decodeIfPresent([String: Decimal].self, forKey: .byPlatform) ?? [:]
    }

    var valueHUF: Decimal { valueEUR * fxRate }
    var gainEUR: Decimal { valueEUR - costEUR }
    var gainPercent: Double {
        guard costEUR > 0 else { return 0 }
        return ((valueEUR - costEUR) / costEUR).doubleValue * 100
    }
}
