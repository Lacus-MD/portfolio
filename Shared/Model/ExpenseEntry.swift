import Foundation

/// Egy kiadási (vagy bevételi) tétel a kivonatokból.
struct ExpenseEntry: Identifiable, Codable, Hashable {
    /// Stabil azonosító: számla + nap + összeg + a leírás eleje.
    ///
    /// A kivonatok ÁTFEDNEK (a júliusi nyitó egyenlege a júniusi zárója), és
    /// ugyanazt a hónapot újra is be lehet olvasni. UUID-vel minden import
    /// megkétszerezné a költést; ezzel a kulccsal a második import felismeri,
    /// hogy ezt a tételt már láttuk.
    var id: String
    var date: Date
    /// Negatív = kiadás, pozitív = bevétel.
    var amountHUF: Decimal
    var merchant: String
    var category: ExpenseCategory
    /// Melyik számláról — a folyószámla és a hitelkártya külön.
    var account: String
    /// Igaz, ha te sorolted át. Az újraimport ilyenkor NEM írja felül:
    /// a kézi döntés erősebb a szabálynál.
    var manualCategory: Bool = false

    var isExpense: Bool { amountHUF < 0 }
    /// Pozitív összeg a kijelzéshez.
    var magnitude: Decimal { abs(amountHUF) }

    init(id: String, date: Date, amountHUF: Decimal, merchant: String,
         category: ExpenseCategory, account: String, manualCategory: Bool = false) {
        self.id = id; self.date = date; self.amountHUF = amountHUF
        self.merchant = merchant; self.category = category
        self.account = account; self.manualCategory = manualCategory
    }

    /// Kézzel írt dekódoló, mint a többi modellnél: hiányzó kulcsnál a Swift
    /// szintetizált változata hibát dobna az alapérték helyett.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(String.self,  forKey: .id)
        date           = try c.decode(Date.self,    forKey: .date)
        amountHUF      = try c.decode(Decimal.self, forKey: .amountHUF)
        merchant       = try c.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        category       = (try? c.decodeIfPresent(ExpenseCategory.self, forKey: .category))
            .flatMap { $0 } ?? .other
        account        = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        manualCategory = try c.decodeIfPresent(Bool.self, forKey: .manualCategory) ?? false
    }

    /// Az azonosító képzése — egy helyen, hogy az importálók egyformán tegyék.
    static func makeID(account: String, date: Date, amount: Decimal, text: String) -> String {
        let day = ConstituentWatcher.dayKey(date)
        let head = text.prefix(40).trimmingCharacters(in: .whitespaces)
        return "\(account)|\(day)|\(amount)|\(head)"
    }
}
