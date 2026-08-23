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
}
