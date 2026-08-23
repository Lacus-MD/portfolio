import Foundation

/// Egy pozíció a TBSZ-számlán. Kézzel visz be a tulajdonos — a Lightyearnek
/// nincs nyilvános API-ja, tehát a darabszám és az átlagár csak innen jöhet.
struct Holding: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Melyik számláról származik. Egy TBSZ = egy számla, és ugyanaz az alap
    /// állhat több TBSZ-évben is — ezért nem az ISIN önmagában a kulcs,
    /// hanem az (ISIN, számla) pár.
    var account: String = Holding.manualAccount
    /// Az ISIN az elsődleges kulcs: a Börse Frankfurt API is ez alapján ad árat,
    /// és a tickerrel ellentétben tőzsdénként nem változik.
    var isin: String
    var ticker: String
    var name: String
    var quantity: Decimal
    /// Átlagos bekerülési ár EUR-ban, darabonként (a Lightyear így mutatja).
    var averageCost: Decimal
    /// A TBSZ gyűjtőéve — ebből számoljuk a 3 és 5 éves fordulónapot.
    var tbszYear: Int

    /// A bekerülési érték FORINTBAN, a vásárlások napi árfolyamán számolva:
    /// Σ (vétel EUR-ban × aznapi EUR/HUF). Ez teszi lehetővé, hogy az
    /// árfolyamnyereséget és a devizahatást szét lehessen választani.
    /// `nil`, ha kézzel vitted be a pozíciót és nincs meg a vásárlások dátuma.
    var costHUF: Decimal?

    var costBasis: Decimal { quantity * averageCost }

    /// Kézzel írt dekódoló, mert a Swift szintetizált változata NEM használja
    /// a property alapértékét hiányzó kulcsnál — `keyNotFound` hibát dob.
    ///
    /// Ez korábban valódi adatvesztést okozott: valahányszor új mezőt kapott a
    /// modell, a már lementett állomány dekódolhatatlanná vált, a betöltés
    /// üreset adott vissza, és a következő mentés felülírta a jó adatot.
    /// Minden később hozzávett mezőt `decodeIfPresent`-tel olvasunk.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(UUID.self,    forKey: .id) ?? UUID()
        account     = try c.decodeIfPresent(String.self,  forKey: .account) ?? Holding.manualAccount
        isin        = try c.decode(String.self,           forKey: .isin)
        ticker      = try c.decode(String.self,           forKey: .ticker)
        name        = try c.decodeIfPresent(String.self,  forKey: .name) ?? ticker
        quantity    = try c.decode(Decimal.self,          forKey: .quantity)
        averageCost = try c.decode(Decimal.self,          forKey: .averageCost)
        tbszYear    = try c.decodeIfPresent(Int.self,     forKey: .tbszYear)
                        ?? Calendar.current.component(.year, from: Date())
        costHUF     = try c.decodeIfPresent(Decimal.self, forKey: .costHUF)
    }

    init(id: UUID = UUID(), account: String = Holding.manualAccount,
         isin: String, ticker: String, name: String,
         quantity: Decimal, averageCost: Decimal, tbszYear: Int, costHUF: Decimal? = nil) {
        self.id = id; self.account = account; self.isin = isin; self.ticker = ticker
        self.name = name; self.quantity = quantity; self.averageCost = averageCost
        self.tbszYear = tbszYear; self.costHUF = costHUF
    }
}

extension Holding {
    /// Kézzel bevitt pozíciók gyűjtőszámlája.
    static let manualAccount = "manuális"

    /// A verifikált Vanguard UCITS ETF-ek: mindegyikre adott árat a Xetra
    /// ISIN-lekérdezés a 2026-08-20-i ellenőrzéskor.
    static let catalog: [(isin: String, ticker: String, name: String)] = [
        ("IE00BK5BQT80", "VWCE", "Vanguard FTSE All-World UCITS ETF (Acc)"),
        ("IE00B3RBWM25", "VWRL", "Vanguard FTSE All-World UCITS ETF (Dist)"),
        ("IE00B3XXRP09", "VUSA", "Vanguard S&P 500 UCITS ETF (Dist)"),
        ("IE00B8GKDB10", "VHYL", "Vanguard FTSE All-World High Dividend Yield (Dist)"),
        ("IE00B3VVMM84", "VFEM", "Vanguard FTSE Emerging Markets UCITS ETF (Dist)"),
        ("IE00B945VV12", "VEUR", "Vanguard FTSE Developed Europe UCITS ETF (Dist)"),
        ("IE00BG47KH54", "VAGF", "Vanguard Global Aggregate Bond UCITS ETF (Acc)"),
    ]
}
