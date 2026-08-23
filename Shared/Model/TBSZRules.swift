import Foundation

/// A TBSZ feltörésének adóterhe sávonként.
///
/// **Ezek szerkeszthető alapértékek, nem az app állításai a jogról.**
/// A kulcsok jogszabálytól függenek és változnak; a 2025-ös módosítás például
/// bevezette a szochót az addig csak szja-val terhelt konstrukcióba. Az app
/// azt számolja ki, ami aritmetika — a kulcs helyességét neked kell
/// ellenőrizned a NAV-nál vagy a számlavezetődnél.
///
/// Forrás az alapértékekhez (2026-08-21-i állapot): RSM Hungary és
/// szjabevallas2026.hu — a 2025. január 1. UTÁN nyitott számlákra
/// 28% / 18% / 0%, az az előtt nyitottakra 15% / 10% / 0% (szocho nélkül).
struct TBSZRules: Codable, Hashable {
    /// A gyűjtőévet követő 3. év végéig.
    var earlyPct: Double
    /// A 3. és az 5. év vége között.
    var reducedPct: Double
    /// Az 5. év vége után.
    var maturePct: Double

    /// A 2025. január 1. után nyitott számlák alapértéke: szja + szocho.
    static let post2025 = TBSZRules(earlyPct: 28, reducedPct: 18, maturePct: 0)
    /// A 2025 előtt nyitottaké: csak szja.
    static let pre2025 = TBSZRules(earlyPct: 15, reducedPct: 10, maturePct: 0)

    /// A gyűjtőév alapján javasolt alapérték.
    static func suggested(forCollectionYear year: Int) -> TBSZRules {
        year >= 2025 ? .post2025 : .pre2025
    }

    init(earlyPct: Double, reducedPct: Double, maturePct: Double) {
        self.earlyPct = earlyPct; self.reducedPct = reducedPct; self.maturePct = maturePct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        earlyPct   = try c.decodeIfPresent(Double.self, forKey: .earlyPct) ?? 28
        reducedPct = try c.decodeIfPresent(Double.self, forKey: .reducedPct) ?? 18
        maturePct  = try c.decodeIfPresent(Double.self, forKey: .maturePct) ?? 0
    }
}

/// Egy feltörési forgatókönyv: mikortól, mekkora kulccsal, és mennyi marad.
struct TBSZScenario: Identifiable {
    var id: String { label }
    let label: String
    /// Mikortól érvényes ez a kulcs. `nil` = már most.
    let from: Date?
    let ratePct: Double
    /// Az adóalap: a nyereség, nem a teljes egyenleg.
    let taxableGain: Decimal
    let tax: Decimal
    /// Amennyi ténylegesen a kezedben marad, ha a mai értéken törnéd fel.
    let netWithdrawal: Decimal
    /// Hány nap múlva lép életbe. Negatív/0 = már most.
    let daysAway: Int

    var isAvailableNow: Bool { daysAway <= 0 }
}

enum TBSZCalculator {

    /// A gyűjtőévet követő 3., illetve 5. év utolsó napja.
    /// A közös rétegben él, mert a widget és az óra is használhatja.
    static func milestones(collectionYear: Int) -> (threeYear: Date, fiveYear: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        guard let three = calendar.date(from: DateComponents(year: collectionYear + 3,
                                                             month: 12, day: 31)),
              let five = calendar.date(from: DateComponents(year: collectionYear + 5,
                                                            month: 12, day: 31))
        else { return nil }
        return (three, five)
    }

    /// A gyűjtőév utolsó napja: eddig lehet befizetni erre a TBSZ-re.
    static func collectionYearEnd(_ year: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest") ?? .current
        return calendar.date(from: DateComponents(year: year, month: 12, day: 31))
    }

    /// Kiszámolja a három sávot a MAI értéken.
    ///
    /// Fontos: mindhárom szám a **mai** egyenleggel számol. Nem jóslat arról,
    /// mennyi lesz a pénzed három vagy öt év múlva — azt senki nem tudja.
    /// Azt mutatja meg, hogy a MOSTANI nyereségedből mennyit vinne el az adó,
    /// ha az adott sávban törnéd fel.
    static func scenarios(value: Decimal, deposits: Decimal,
                          collectionYear: Int, rules: TBSZRules,
                          now: Date = Date()) -> [TBSZScenario] {
        // Adóalap a nyereség; veszteségre nincs adó.
        let gain = max(0, value - deposits)
        let milestones = milestones(collectionYear: collectionYear)

        func days(to date: Date?) -> Int {
            guard let date else { return 0 }
            return Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0
        }

        func scenario(_ label: String, _ from: Date?, _ ratePct: Double) -> TBSZScenario {
            let tax = gain * Decimal(ratePct) / 100
            return TBSZScenario(
                label: label, from: from, ratePct: ratePct,
                taxableGain: gain, tax: tax,
                netWithdrawal: value - tax,
                daysAway: days(to: from)
            )
        }

        return [
            scenario("Ma", nil, rules.earlyPct),
            scenario("3 év után", milestones?.threeYear, rules.reducedPct),
            scenario("5 év után", milestones?.fiveYear, rules.maturePct),
        ]
    }
}
