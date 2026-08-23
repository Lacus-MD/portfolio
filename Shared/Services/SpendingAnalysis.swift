import Foundation

/// Havi pénzáram-bontás és ismétlődő terhelések.
///
/// Mindkettő a beolvasott tételekből számol — nincs feltevés, nincs becslés.
enum SpendingAnalysis {

    // MARK: - Havi bontás

    struct Month: Identifiable, Hashable {
        var id: Date { start }
        /// A hónap első napja.
        let start: Date
        let income: Decimal
        /// Fix költség: törlesztés, rezsi, biztosítás, előfizetés, banki díj.
        let fixed: Decimal
        /// Változó költés: minden más valódi kiadás.
        let variable: Decimal
        /// Saját számlára vagy befektetésbe átvezetve — NEM költés.
        let moved: Decimal

        var spending: Decimal { fixed + variable }
        /// Mennyi maradt: bevétel mínusz minden kimenő. Negatív = a
        /// számlaegyenlegből fogyott.
        var remainder: Decimal { income - fixed - variable - moved }
        /// A fix költség aránya a bevételhez.
        var fixedShare: Double? {
            guard income > 0 else { return nil }
            return (fixed / income).doubleValue * 100
        }
    }

    static func months(_ entries: [ExpenseEntry],
                       calendar: Calendar = .current) -> [Month] {
        let grouped = Dictionary(grouping: entries) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date))
                ?? $0.date
        }
        return grouped.map { start, items in
            var income: Decimal = 0, fixed: Decimal = 0
            var variable: Decimal = 0, moved: Decimal = 0
            for item in items {
                if item.amountHUF > 0 { income += item.amountHUF }
                else if !item.category.isSpending { moved += item.magnitude }
                else if item.category.isFixed { fixed += item.magnitude }
                else { variable += item.magnitude }
            }
            return Month(start: start, income: income, fixed: fixed,
                         variable: variable, moved: moved)
        }
        .sorted { $0.start > $1.start }
    }

    // MARK: - Ismétlődő terhelések

    struct Recurring: Identifiable, Hashable {
        var id: String { merchant }
        let merchant: String
        let category: ExpenseCategory
        /// Hány KÜLÖNBÖZŐ hónapban fordult elő.
        let months: Int
        let monthlyAverage: Decimal
        /// A legnagyobb eltérés az átlagtól, arányosan. Minél kisebb, annál
        /// inkább előfizetés és annál kevésbé bevásárlás.
        let spread: Double

        var yearly: Decimal { monthlyAverage * 12 }
    }

    /// Ismétlődő, ÁLLANDÓ ÖSSZEGŰ terhelések — vagyis előfizetések.
    ///
    /// A puszta „ugyanaz a kereskedő több hónapban" szabály kevés: a Lidl és
    /// a benzinkút is minden hónapban ott van. Mérve a tulajdonos három
    /// hónapján: az így kapott lista fele bevásárlás volt. Az előfizetést az
    /// különbözteti meg, hogy az ÖSSZEG is állandó — ezért a szórásra is
    /// szűrünk (`maxSpread`), és havonta legfeljebb egy terhelést fogadunk el.
    static func recurring(_ entries: [ExpenseEntry],
                          minimumMonths: Int = 3,
                          maxSpread: Double = 0.08,
                          minimumAmount: Decimal = 300,
                          calendar: Calendar = .current) -> [Recurring] {
        let expenses = entries.filter { $0.isExpense && $0.category.isSpending }
        let byMerchant = Dictionary(grouping: expenses, by: \.merchant)

        return byMerchant.compactMap { merchant, items -> Recurring? in
            // Havonta EGY terhelés: aki havonta ötször vásárol ugyanott, az
            // nem előfizető, hanem törzsvásárló.
            let byMonth = Dictionary(grouping: items) {
                calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date))
                    ?? $0.date
            }
            guard byMonth.count >= minimumMonths,
                  byMonth.values.allSatisfy({ $0.count == 1 }) else { return nil }

            let amounts = byMonth.values.compactMap { $0.first?.magnitude }
            let average = amounts.reduce(Decimal(0), +) / Decimal(amounts.count)
            guard average >= minimumAmount, average > 0 else { return nil }

            let spread = amounts
                .map { abs(($0 - average).doubleValue) / average.doubleValue }
                .max() ?? 0
            guard spread <= maxSpread else { return nil }

            return Recurring(merchant: merchant,
                             category: items[0].category,
                             months: byMonth.count,
                             monthlyAverage: average,
                             spread: spread)
        }
        .sorted { $0.yearly > $1.yearly }
    }
}
