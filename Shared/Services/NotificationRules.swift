import Foundation

/// Pure notification decisions. The app adapter turns these events into
/// UNNotificationRequests; tests never need notification permission.
enum NotificationRules {
    enum Direction: String, Hashable {
        case up, down, incoming, outgoing
    }

    struct MarketInput: Hashable, Sendable {
        let id: String
        let name: String
        let symbol: String
        let changePct: Double
        let price: Decimal
        let currency: String
    }

    struct MarketEvent: Hashable, Sendable {
        let input: MarketInput
        let direction: Direction

        var key: String { "\(input.id)|\(direction.rawValue)" }
    }

    static func marketEvents(_ inputs: [MarketInput], thresholdPct: Double = 3,
                             limit: Int = 6) -> [MarketEvent] {
        var seen = Set<String>()
        return inputs
            .filter { abs($0.changePct) >= thresholdPct }
            .sorted { abs($0.changePct) > abs($1.changePct) }
            .compactMap { input in
                let direction: Direction = input.changePct >= 0 ? .up : .down
                let event = MarketEvent(input: input, direction: direction)
                return seen.insert(event.key).inserted ? event : nil
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    struct BankInput: Hashable, Sendable {
        let id: String
        let account: String
        let merchant: String
        let amountHUF: Decimal
    }

    struct BankEvent: Hashable, Sendable {
        let input: BankInput
        let direction: Direction

        var key: String { input.id }
    }

    static func bankEvents(_ inputs: [BankInput], thresholdHUF: Decimal = 25_000,
                           limit: Int = 8) -> [BankEvent] {
        var seen = Set<String>()
        return inputs
            .filter { abs($0.amountHUF) >= thresholdHUF }
            .sorted { abs($0.amountHUF) > abs($1.amountHUF) }
            .compactMap { input in
                let direction: Direction = input.amountHUF >= 0 ? .incoming : .outgoing
                let event = BankEvent(input: input, direction: direction)
                return seen.insert(event.key).inserted ? event : nil
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    struct Deduplicator {
        private(set) var stamps: [String: Date] = [:]
        var retention: TimeInterval = 3 * 24 * 3600

        mutating func shouldEmit(_ key: String, now: Date) -> Bool {
            prune(now: now)
            guard stamps[key] == nil else { return false }
            stamps[key] = now
            return true
        }

        mutating func prune(now: Date) {
            let cutoff = now.addingTimeInterval(-retention)
            stamps = stamps.filter { $0.value >= cutoff }
        }
    }
}
