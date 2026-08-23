import Foundation

/// A hitelkártya-kivonat fizetési adatai.
///
/// A kivonat kiírja őket, eddig csak nem kezdtünk velük semmit. A határidő
/// lekésése drága — a bank késedelmi kamatot és díjat számol —, ezért ez az
/// egyetlen adat az appban, ami ÉRTESÍTÉST is érdemel.
struct CreditCardStatus: Codable, Hashable {
    var platform: String
    var totalDebt: Decimal
    var minimumPayment: Decimal?
    var dueDate: Date?
    var creditLimit: Decimal?
    /// A kivonat kelte — ebből tudjuk, mennyire friss az adat.
    var asOf: Date

    /// Hány nap van a határidőig. Negatív = már lejárt.
    func daysUntilDue(_ now: Date = Date()) -> Int? {
        guard let dueDate else { return nil }
        return Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: now),
            to: Calendar.current.startOfDay(for: dueDate)).day
    }

    /// Igaz, ha a határidő már elmúlt — ilyenkor az adat elavult, nem
    /// sürgős: új kivonat kell. Ezt meg kell különböztetni a „most jár le"
    /// esettől, különben az app hónapokig riogatna egy régi dátummal.
    var isStale: Bool { (daysUntilDue() ?? 0) < 0 }

    init(platform: String, totalDebt: Decimal, minimumPayment: Decimal? = nil,
         dueDate: Date? = nil, creditLimit: Decimal? = nil, asOf: Date = Date()) {
        self.platform = platform; self.totalDebt = totalDebt
        self.minimumPayment = minimumPayment; self.dueDate = dueDate
        self.creditLimit = creditLimit; self.asOf = asOf
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        platform       = try c.decode(String.self, forKey: .platform)
        totalDebt      = try c.decodeIfPresent(Decimal.self, forKey: .totalDebt) ?? 0
        minimumPayment = try c.decodeIfPresent(Decimal.self, forKey: .minimumPayment)
        dueDate        = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        creditLimit    = try c.decodeIfPresent(Decimal.self, forKey: .creditLimit)
        asOf           = try c.decodeIfPresent(Date.self, forKey: .asOf) ?? Date()
    }
}
