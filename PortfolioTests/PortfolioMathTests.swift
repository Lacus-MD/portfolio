import Foundation
import XCTest
@testable import Portfolio

final class PortfolioMathTests: XCTestCase {
    func testHUFConversionLeavesAmountUnchanged() {
        let prices = PortfolioMath.Prices(fxRate: 400, usdRate: 360)

        assertDecimalEqual(
            PortfolioMath.convertToHUF(Decimal(123_456), currency: "HUF", prices: prices),
            Decimal(123_456)
        )
    }

    func testEURAndUSDConversionUseTheProvidedRates() {
        let prices = PortfolioMath.Prices(fxRate: 400, usdRate: 360)

        assertDecimalEqual(
            PortfolioMath.convertToHUF(Decimal(10), currency: "EUR", prices: prices),
            Decimal(4_000)
        )
        assertDecimalEqual(
            PortfolioMath.convertToHUF(Decimal(10), currency: "USD", prices: prices),
            Decimal(3_600)
        )
    }

    func testUnknownCurrencyAndMissingUSDRateReturnZero() {
        let prices = PortfolioMath.Prices(fxRate: 400, usdRate: 0)

        assertDecimalEqual(
            PortfolioMath.convertToHUF(Decimal(10), currency: "USD", prices: prices),
            0
        )
        assertDecimalEqual(
            PortfolioMath.convertToHUF(Decimal(10), currency: "GBP", prices: prices),
            0
        )
    }

    func testNetValueAppliesAccountSpecificConversionSpread() {
        var payload = PortfolioFile.Payload()
        payload.conversionSpread = ["broker": Decimal(string: "0.01")!]
        let holding = Holding(account: "broker", isin: "IE00BK5BQT80", ticker: "VWCE",
                              name: "VWCE", quantity: 2, averageCost: 100,
                              tbszYear: 2026)
        let prices = PortfolioMath.Prices(quotes: [holding.isin: 100], fxRate: 400)

        assertDecimalEqual(
            PortfolioMath.netValueHUF(of: holding, in: payload, prices: prices) ?? 0,
            79_200
        )
    }

    func testTotalDepositsExcludeCurrentAccountsAndInternalTransfers() {
        var payload = PortfolioFile.Payload()
        payload.platforms = [
            Platform(id: "broker", name: "Broker", kind: .brokerage),
            Platform(id: "current", name: "Current", kind: .current),
        ]
        payload.deposits = [
            Deposit(account: "broker", date: Date(), amountHUF: 100_000),
            Deposit(account: "broker", date: Date(), amountHUF: 25_000, isInternal: true),
            Deposit(account: "current", date: Date(), amountHUF: 500_000),
        ]

        assertDecimalEqual(PortfolioMath.depositsHUF(payload), 125_000)
    }

    func testDailyTotalsFallBackToLegacySnapshotShape() {
        let snapshot = Snapshot(date: Date(), valueEUR: 10, costEUR: 8, fxRate: 400)
        var payload = PortfolioFile.Payload()
        payload.snapshots = [snapshot]

        XCTAssertEqual(PortfolioMath.dailyTotalsHUF(payload), [4_000])
    }
}
