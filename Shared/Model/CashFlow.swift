import Foundation

/// Egy forintos befizetés a számlára. Az XIRR ezekből számol: minden befizetés
/// egy kimenő pénzáram a saját dátumán, a mai portfólióérték pedig a bejövő.
struct Deposit: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var account: String = Holding.manualAccount
    var date: Date
    var amountHUF: Decimal
    /// Igaz, ha a pénz KÉT KÖVETETT platform között mozgott (pl. Revolut
    /// folyószámla → megtakarítás). Platformon belül befizetés — a platform
    /// XIRR-je szempontjából valódi pénzbeáramlás —, de a TELJES vagyon
    /// szempontjából nem új pénz, ezért az összesített hozamból kimarad.
    /// Enélkül ugyanaz a forint kétszer számítana befizetésnek.
    var isInternal: Bool = false

    init(id: UUID = UUID(), account: String = Holding.manualAccount,
         date: Date, amountHUF: Decimal, isInternal: Bool = false) {
        self.id = id; self.account = account; self.date = date
        self.amountHUF = amountHUF; self.isInternal = isInternal
    }

    /// Lásd a `Holding` dekódolójánál: hiányzó kulcsnál a Swift nem esik vissza
    /// az alapértékre, ezért kézzel olvassuk a később hozzávett mezőket.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(UUID.self,   forKey: .id) ?? UUID()
        account   = try c.decodeIfPresent(String.self, forKey: .account) ?? Holding.manualAccount
        date      = try c.decode(Date.self,            forKey: .date)
        amountHUF = try c.decode(Decimal.self,         forKey: .amountHUF)
        isInternal = try c.decodeIfPresent(Bool.self,  forKey: .isInternal) ?? false
    }
}

/// Egy levont díj. Külön tételként tartjuk, nem a bekerülési árban: a Lightyear
/// átlagára sem tartalmazza, és így külön is meg lehet mutatni, mennyit vitt el.
struct FeeItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case deposit    = "befizetés"
        case conversion = "átváltás"
        case trade      = "kereskedés"
    }
    var id: UUID = UUID()
    var account: String = Holding.manualAccount
    var date: Date
    var amountHUF: Decimal
    var kind: Kind

    init(id: UUID = UUID(), account: String = Holding.manualAccount,
         date: Date, amountHUF: Decimal, kind: Kind) {
        self.id = id; self.account = account; self.date = date
        self.amountHUF = amountHUF; self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(UUID.self,   forKey: .id) ?? UUID()
        account   = try c.decodeIfPresent(String.self, forKey: .account) ?? Holding.manualAccount
        date      = try c.decode(Date.self,            forKey: .date)
        amountHUF = try c.decode(Decimal.self,         forKey: .amountHUF)
        kind      = try c.decodeIfPresent(Kind.self,   forKey: .kind) ?? .trade
    }
}
