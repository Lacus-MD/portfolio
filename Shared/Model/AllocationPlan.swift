import Foundation

/// Célállapot: egy platform várható aránycélja a befektethető vagyonban.
struct AllocationTarget: Codable, Hashable, Identifiable {
    let platformID: String
    var percent: Double
    var id: String { platformID }

    init(platformID: String, percent: Double = 0) {
        self.platformID = platformID
        self.percent = percent
    }

    /// Százalék, 0...100 tartományban.
    var clampedPercent: Double {
        max(0, min(100, percent))
    }
}

/// Egy célallokáció alapján kiszámolt javaslat az újonnan beteszhető pénzre.
struct AllocationSuggestion: Identifiable, Hashable {
    let id = UUID()
    let platformID: String
    let platformName: String
    let platformAccent: Platform.Accent?

    /// Aktuális abszolút érték a platformon.
    let currentValueHUF: Decimal
    /// Célaránynak megfelelő érték a meglévő + új pénz után.
    let targetValueHUF: Decimal
    /// Jelenlegi arány a teljes befektethető vagyonban (0...1).
    let currentShare: Double
    /// A célarány százalékban, normalizálás után.
    let targetPercent: Double
    /// Ennyivel ajánljuk feltölteni, ha ezt az új pénzt cél szerint osztod.
    let recommendAmount: Decimal

    /// A célarány szerint az új pénz utáni elméleti vagyon.
    var plannedValueHUF: Decimal { currentValueHUF + recommendAmount }
}

/// A naptár nézetben használható esemény.
struct MaturityCalendarEvent: Identifiable, Hashable {
    enum Kind: String, Codable, Hashable {
        case collectionDeadline   // gyűjtőév vége (TBSZ)
        case threeYear           // TBSZ 3 éves forduló
        case fiveYear            // TBSZ 5 éves forduló
        case savingsRate         // megtakarítási számlán lévő becsült kamatkör
    }

    let id = UUID()
    let kind: Kind
    let platformID: String?
    let title: String
    let subtitle: String
    let date: Date

    /// A mai naptól mért nappontosság, pozitív = még hátra.
    let daysFromToday: Int
}

/// Adatfrissességi mutató egy-egy forrásnál.
enum FreshnessState: Int, Codable, Hashable, Comparable {
    case fresh = 0
    case good = 1
    case stale = 2
    case outOfDate = 3
    case missing = 4

    static func < (lhs: FreshnessState, rhs: FreshnessState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct DataFreshnessItem: Identifiable, Hashable {
    let id = UUID()
    let category: String
    let title: String
    let detail: String
    let lastUpdated: Date?
    let state: FreshnessState
}

