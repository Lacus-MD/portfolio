import Foundation

/// „Mi lenne, ha…" számoló.
///
/// **Nem előrejelzés.** Az app nem tudja, mennyit fog hozni egy világindex —
/// azt senki nem tudja. Ez egy kamatos-kamat számológép, aminek a feltevéseit
/// TE adod meg: ha ennyit hozna évente, és ennyit teszel be havonta, akkor
/// ennyi lenne. A felület ezt ki is mondja, hogy ne látszódjon jóslatnak.
struct Scenario: Codable, Hashable {
    /// Feltételezett éves hozam százalékban.
    var annualReturnPct: Double = 6
    /// Havi befizetés forintban.
    var monthlyHUF: Decimal = 100_000
    /// Meddig számolunk.
    var targetDate: Date

    init(annualReturnPct: Double = 6, monthlyHUF: Decimal = 100_000, targetDate: Date) {
        self.annualReturnPct = annualReturnPct
        self.monthlyHUF = monthlyHUF
        self.targetDate = targetDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        annualReturnPct = try c.decodeIfPresent(Double.self,  forKey: .annualReturnPct) ?? 6
        monthlyHUF      = try c.decodeIfPresent(Decimal.self, forKey: .monthlyHUF) ?? 100_000
        targetDate      = try c.decodeIfPresent(Date.self,    forKey: .targetDate)
            ?? Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
    }
}

struct ScenarioResult {
    let months: Int
    /// A mai vagyon kamatos kamattal a célidőpontig.
    let grownFromToday: Decimal
    /// A jövőbeli havi befizetések összege kamattal.
    let grownFromContributions: Decimal
    /// Amennyit ténylegesen beteszel a célidőpontig.
    let contributed: Decimal
    var total: Decimal { grownFromToday + grownFromContributions }
    /// A hozamból származó rész — ennyi NEM a te befizetésed.
    var earned: Decimal { total - contributed }
}

enum ScenarioCalculator {

    /// Havi kamatozású jövőérték: a mai összeg növekedése plusz a havi
    /// befizetések járadéka. Havi bontásban számol, mert a befizetés is havi.
    static func project(currentHUF: Decimal, scenario: Scenario,
                        from now: Date = Date()) -> ScenarioResult {
        let months = max(0, Calendar.current.dateComponents(
            [.month], from: now, to: scenario.targetDate).month ?? 0)
        guard months > 0 else {
            return ScenarioResult(months: 0, grownFromToday: currentHUF,
                                  grownFromContributions: 0, contributed: 0)
        }

        // Éves kulcsból havi: a 12. gyök, nem az osztás — különben a
        // kamatos kamat miatt évente néhány tized százalékot tévednénk.
        let annual = scenario.annualReturnPct / 100
        let monthly = pow(1 + annual, 1.0 / 12) - 1
        let n = Double(months)
        let growth = pow(1 + monthly, n)

        let grownToday = Decimal(currentHUF.doubleValue * growth)
        // Járadék jövőértéke; nulla kamatnál egyszerű szorzás.
        let annuityFactor = monthly == 0 ? n : (growth - 1) / monthly
        let grownContrib = Decimal(scenario.monthlyHUF.doubleValue * annuityFactor)

        return ScenarioResult(
            months: months,
            grownFromToday: grownToday,
            grownFromContributions: grownContrib,
            contributed: scenario.monthlyHUF * Decimal(months)
        )
    }
}
