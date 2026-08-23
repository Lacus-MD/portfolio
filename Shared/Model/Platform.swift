import Foundation

/// Egy követett platform (számla). A redizájn ezt teszi a szervező egységgé:
/// a kezdőképernyő platformkártyákat sorol, az összehasonlító nézet
/// platformonként egy görbét rajzol.
struct Platform: Identifiable, Codable, Hashable {

    /// Mit tart a platform. Ez a megkülönböztetés azért kell, mert a
    /// **Revolut Savings nem értékpapír**: nincs ISIN-je, darabszáma és
    /// árfolyama — kamatozó egyenleg. A régi modell csak pozíciót ismert.
    enum Kind: String, Codable {
        case brokerage   // értékpapírszámla (Lightyear, TBSZ)
        case savings     // kamatozó készpénz (Revolut Savings, széf)
        /// KÖTELEZETTSÉG: hitelkártya, folyószámlahitel. Az értéke negatív.
        ///
        /// Külön típus, mert a hozamszámításból ki kell maradnia. A tartozás
        /// csökkenti a nettó vagyont — ez helyes —, de nem befektetési
        /// veszteség: beleszámolva a „hozam" −44%-ot mutatott attól, hogy
        /// van egy hitelkártyád.
        case credit
        /// FOLYÓSZÁMLA: tranzakciós számla, nem befektetés.
        ///
        /// Külön típus, ugyanabból az okból, amiért a `credit` is az: az
        /// értéke jogosan benne van a nettó vagyonban, de a HOZAMBAN nincs
        /// keresnivalója. Ide fizetés érkezik és innen költesz — mérve az
        /// OTP folyószámla „+51,43% hozamot” mutatott, ami a teljes portfólió
        /// nyereségének 95%-át adta. Az nem befektetési eredmény volt, hanem
        /// az, hogy megjött a fizetés.
        case current
    }

    /// Igaz, ha a platform tartozás, nem eszköz.
    var isLiability: Bool { kind == .credit }

    /// Igaz, ha a számla tranzakciós: az értéke számít, a hozama nem.
    var isTransactional: Bool { kind == .current }

    /// Igaz, ha a platformra értelmes hozamot számolni.
    var hasMeaningfulGain: Bool { !isLiability && !isTransactional }

    /// A handoff három akcentusa, sorrendben.
    /// A platform színe. A nevek TÖRTÉNETIEK: a tényleges árnyalat a témából
    /// jön, tehát a „coral” nem feltétlenül korall. A sorrend számít — az új
    /// platform az első SZABAD színt kapja, és az első három szándékosan
    /// ugyanaz maradt, mint amikor még csak három volt.
    enum Accent: String, Codable, CaseIterable {
        case coral, mint, lilac, ochre, azure, moss

        /// Hányadik akcentus a témában.
        var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    var id: String            // a számla azonosítója, pl. "LY-4WY38ZH"
    var name: String          // megjelenített név, pl. "TBSZ · VWCE"
    var kind: Kind
    var accent: Accent
    var monogram: String      // két betű a jelvényhez: VW / LY / RS
    var tbszYear: Int?

    init(id: String, name: String, kind: Kind = .brokerage,
         accent: Accent = .coral, monogram: String? = nil, tbszYear: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.accent = accent
        self.monogram = monogram ?? Platform.defaultMonogram(for: name)
        self.tbszYear = tbszYear
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(String.self, forKey: .id)
        name     = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        kind     = try c.decodeIfPresent(Kind.self,   forKey: .kind) ?? .brokerage
        accent   = try c.decodeIfPresent(Accent.self, forKey: .accent) ?? .coral
        monogram = try c.decodeIfPresent(String.self, forKey: .monogram)
                    ?? Platform.defaultMonogram(for: name)
        tbszYear = try c.decodeIfPresent(Int.self,    forKey: .tbszYear)
    }

    static func defaultMonogram(for name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        if words.count >= 2 {
            return (String(words[0].prefix(1)) + String(words[1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// Kamatozó készpénz-eszköz — a Revolut Savings és társai.
/// Nem `Holding`: nincs ISIN, darabszám és piaci ár.
struct CashAsset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var platform: String
    var name: String
    var balance: Decimal
    var currency: String
    /// Meghirdetett éves kamat, tájékoztatásul. Nem számolunk vele előre —
    /// a tényleges jóváírás a kivonatból jön.
    var annualRatePct: Double?
    /// A kivonatból MÉRT nettó napi kamatláb (pl. 0,0000493 ≈ 1,80% évesítve).
    ///
    /// Nem a meghirdetett EBKM: a ténylegesen jóváírt kamat annak 72%-a
    /// (28% levonás). A meghirdetett kulccsal vetítve az app rendszeresen
    /// többet mutatna a valóságnál. `nil`, ha a kivonatból nem volt mérhető.
    var netDailyRate: Decimal?

    /// Melyik NAP állapotát tükrözi az egyenleg.
    ///
    /// Kritikus, mert az app **nem követi magától a napi kamatot**: a
    /// megtakarítás egyenlege a legutóbbi kivonat záró értékén áll, amíg új
    /// kivonatot nem olvasol be. Enélkül a szám némán öregedne.
    var asOf: Date?

    init(id: UUID = UUID(), platform: String, name: String,
         balance: Decimal, currency: String,
         annualRatePct: Double? = nil, asOf: Date? = nil,
         netDailyRate: Decimal? = nil) {
        self.id = id; self.platform = platform; self.name = name
        self.balance = balance; self.currency = currency
        self.annualRatePct = annualRatePct; self.asOf = asOf
        self.netDailyRate = netDailyRate
    }

    /// Hány nap telt el a kivonat óta.
    func daysSinceStatement(_ now: Date = Date()) -> Int {
        guard let asOf else { return 0 }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: asOf),
            to: Calendar.current.startOfDay(for: now)
        ).day ?? 0
        return max(0, days)   // visszafelé sosem vetítünk
    }

    /// A becsült mai egyenleg: a kivonat záró értéke, napi kamatos kamattal
    /// a mai napig görgetve.
    ///
    /// **Ez becslés, nem mérés.** A Revolut naponta írja jóvá a kamatot a
    /// megnövelt egyenlegre, ezért kamatos kamat. Amit NEM tud: az időközbeni
    /// be- és kifizetéseidet, és azt, ha a Revolut közben kulcsot változtat.
    /// Ezért kell hetente egy import — az visszaigazítja a valósághoz.
    func estimatedBalance(on now: Date = Date()) -> Decimal {
        guard let rate = netDailyRate, rate > 0 else { return balance }
        let days = daysSinceStatement(now)
        guard days > 0 else { return balance }
        // Óvatosság: hosszú szünet után a becslés egyre bizonytalanabb, de
        // attól még nem hamis — a felület jelzi, hány napos.
        let factor = pow(1 + rate.doubleValue, Double(days))
        return Decimal(balance.doubleValue * factor)
    }

    /// A becsült felhalmozott kamat a kivonat óta.
    func estimatedInterest(on now: Date = Date()) -> Decimal {
        estimatedBalance(on: now) - balance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decodeIfPresent(UUID.self,    forKey: .id) ?? UUID()
        platform      = try c.decode(String.self,           forKey: .platform)
        name          = try c.decodeIfPresent(String.self,  forKey: .name) ?? "Megtakarítás"
        balance       = try c.decode(Decimal.self,          forKey: .balance)
        currency      = try c.decodeIfPresent(String.self,  forKey: .currency) ?? "HUF"
        annualRatePct = try c.decodeIfPresent(Double.self,  forKey: .annualRatePct)
        asOf          = try c.decodeIfPresent(Date.self,    forKey: .asOf)
        netDailyRate  = try c.decodeIfPresent(Decimal.self, forKey: .netDailyRate)
    }
}
