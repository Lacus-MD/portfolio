import Foundation

/// A portfolio-wide data quality signal. This is intentionally separate from
/// `FreshnessState`: freshness answers "how old is it?", while reconciliation
/// answers "can I trust the number and what should I check?".
enum ReconciliationSeverity: Int, Codable, Hashable, Comparable {
    case clear = 0
    case notice = 1
    case warning = 2
    case critical = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ReconciliationIssue: Identifiable, Codable, Hashable {
    /// Stable IDs matter here: the report is recomputed during SwiftUI updates,
    /// so a UUID would make every row look like a new item on every render.
    let id: String
    let severity: ReconciliationSeverity
    let title: String
    let detail: String
}

struct ReconciliationRow: Identifiable, Codable, Hashable {
    let id: String
    let platformName: String
    let source: String
    let valueHUF: Decimal
    let depositsHUF: Decimal?
    let changeHUF: Decimal?
    let severity: ReconciliationSeverity
    let detail: String
}

struct ReconciliationReport: Codable, Hashable {
    let generatedAt: Date
    let rows: [ReconciliationRow]
    let issues: [ReconciliationIssue]

    var severity: ReconciliationSeverity {
        issues.map(\.severity).max() ?? .clear
    }

    var isClear: Bool { severity == .clear }
}
