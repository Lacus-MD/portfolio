import Foundation
import XCTest
@testable import Portfolio

final class NotificationRuleTests: XCTestCase {
    func testMarketThresholdIsInclusiveAndDeduplicatesAccounts() {
        let moves = [
            NotificationRules.MarketInput(id: "VWCE", name: "VWCE", symbol: "VWCE",
                                          changePct: 3, price: 100, currency: "EUR"),
            NotificationRules.MarketInput(id: "VWCE", name: "VWCE", symbol: "VWCE",
                                          changePct: 4, price: 101, currency: "EUR"),
            NotificationRules.MarketInput(id: "VUSA", name: "VUSA", symbol: "VUSA",
                                          changePct: -2.99, price: 100, currency: "EUR"),
        ]

        let events = NotificationRules.marketEvents(moves)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.input.id, "VWCE")
        XCTAssertEqual(events.first?.direction, .up)
    }

    func testMarketDirectionsRemainSeparateAndLimitIsSix() {
        let moves = (0..<8).map { index in
            NotificationRules.MarketInput(id: "I\(index)", name: "I\(index)", symbol: "I\(index)",
                                          changePct: index.isMultiple(of: 2) ? 5 : -4,
                                          price: 1, currency: "EUR")
        }
        let events = NotificationRules.marketEvents(moves)
        XCTAssertEqual(events.count, 6)
        XCTAssertTrue(events.contains { $0.direction == .down })
        XCTAssertTrue(events.contains { $0.direction == .up })
    }

    func testBankThresholdAndLimitUseSignedDirection() {
        let movements = (0..<10).map { index in
            NotificationRules.BankInput(id: "T\(index)", account: "OTP",
                                        merchant: index == 0 ? "" : "Bolt",
                                        amountHUF: index.isMultiple(of: 2) ? 25_000 : -30_000)
        }
        let events = NotificationRules.bankEvents(movements)
        XCTAssertEqual(events.count, 8)
        XCTAssertTrue(events.contains { $0.direction == .incoming })
        XCTAssertTrue(events.contains { $0.direction == .outgoing })
    }

    func testDeduplicatorSeparatesDirectionAndPrunesOldEvents() {
        var dedupe = NotificationRules.Deduplicator()
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(dedupe.shouldEmit("VWCE|up", now: now))
        XCTAssertFalse(dedupe.shouldEmit("VWCE|up", now: now.addingTimeInterval(10)))
        XCTAssertTrue(dedupe.shouldEmit("VWCE|down", now: now.addingTimeInterval(10)))
        XCTAssertTrue(dedupe.shouldEmit("old", now: now.addingTimeInterval(4 * 24 * 3600)))
        XCTAssertTrue(dedupe.shouldEmit("VWCE|up", now: now.addingTimeInterval(4 * 24 * 3600)))
    }
}
