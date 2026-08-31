import Foundation
import XCTest
@testable import Portfolio

final class ImporterFixtureTests: XCTestCase {
    func testLightyearNumberPreservesFractionalSharePrecision() {
        XCTAssertEqual(StatementImporter.number("1.000000000"), Decimal(string: "1")!)
        XCTAssertEqual(StatementImporter.number("0.125000000"), Decimal(string: "0.125")!)
        XCTAssertEqual(StatementImporter.number("1,234.567890"), Decimal(string: "1234.567890")!)
    }

    func testCSVParserStripsBOMAndKeepsQuotedDelimiter() {
        let fields = StatementImporter.parse(
            line: "\u{FEFF}\"Dátum\";\"Leírás; részlet\";\"1,23\"",
            delimiter: ";"
        )

        XCTAssertEqual(fields, ["Dátum", "Leírás; részlet", "1,23"])
        assertDecimalEqual(HungarianCSV.number(fields[2]) ?? 0, Decimal(string: "1.23")!)
    }

    func testOTPAccountFixtureSeparatesCurrentAccountAndKeepsBalance() throws {
        let fixture = try FixtureLoader.string(named: "otp-account", subdirectory: "OTP")
        let result = try OTPImporter.import(text: fixture)
        let repeated = try OTPImporter.import(text: fixture)

        if case .account = result.kind {
            // expected
        } else {
            XCTFail("Expected an OTP current-account import")
        }
        XCTAssertEqual(result.entries.count, 2)
        assertDecimalEqual(result.opening, 1_000_000)
        assertDecimalEqual(result.closing, 1_388_290)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(repeated.entries.count, result.entries.count)
        assertDecimalEqual(repeated.closing, result.closing)
    }

    func testOTPCreditFixtureIsNegativeDebtAndParsesQuotedText() throws {
        let fixture = try FixtureLoader.string(named: "otp-credit", subdirectory: "OTP")
        let result = try OTPImporter.import(text: fixture)
        let repeated = try OTPImporter.import(text: fixture)

        if case .credit = result.kind {
            // expected
        } else {
            XCTFail("Expected an OTP credit-card import")
        }
        XCTAssertEqual(result.entries.count, 1)
        assertDecimalEqual(result.closing, -650_867)
        assertDecimalEqual(result.totalDebt ?? 0, 650_867)
        XCTAssertTrue(result.entries[0].text.contains("KÁVÉ, BELVÁROS"))
        assertDecimalEqual(repeated.closing, result.closing)
    }

    func testRevolutSavingsFixtureKeepsInterestOutOfDeposits() throws {
        let fixture = try FixtureLoader.string(named: "revolut-savings", fileExtension: "csv", subdirectory: "Revolut")
        let result = RevolutImporter.importSavings(csv: fixture, platformID: "revolut-savings")
        let repeated = RevolutImporter.importSavings(csv: fixture, platformID: "revolut-savings")

        assertDecimalEqual(result.asset.balance, 1_000_223)
        XCTAssertEqual(result.deposits.filter(\.isInternal).count, 1)
        XCTAssertEqual(result.deposits.filter { !$0.isInternal }.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("kamat") })
        XCTAssertEqual(result.dailyBalances.count, 3)
        XCTAssertEqual(repeated.deposits.count, result.deposits.count)
        assertDecimalEqual(repeated.asset.balance, result.asset.balance)
    }

    func testRevolutAccountFixtureHandlesQuotedCommaAndSkipsPending() throws {
        let fixture = try FixtureLoader.string(named: "revolut-account", fileExtension: "csv", subdirectory: "Revolut")
        let result = RevolutImporter.importAccount(csv: fixture, platformID: "revolut-account")
        let repeated = RevolutImporter.importAccount(csv: fixture, platformID: "revolut-account")

        assertDecimalEqual(result.asset.balance, 900)
        XCTAssertEqual(result.deposits.count, 2)
        XCTAssertTrue(result.deposits.contains { $0.isInternal && $0.amountHUF == -100 })
        XCTAssertTrue(result.warnings.contains { $0.contains("függő") })
        XCTAssertEqual(repeated.deposits.count, result.deposits.count)
        assertDecimalEqual(repeated.asset.balance, result.asset.balance)
    }

    func testStateTreasuryFixtureHandlesSemicolonAndQuotedName() throws {
        let fixture = try FixtureLoader.string(named: "state-treasury", fileExtension: "csv",
                                               subdirectory: "StateTreasury")
        let result = try StateTreasuryImporter.import(text: fixture,
                                                      accountHint: "allamkincstar-export.csv")
        let repeated = try StateTreasuryImporter.import(text: fixture,
                                                        accountHint: "allamkincstar-export.csv")

        XCTAssertEqual(result.positions, 2)
        assertDecimalEqual(result.asset.balance, 1_234_567)
        XCTAssertEqual(result.account, "treasury-allamkincstar")
        XCTAssertTrue(result.accountName.contains("allamkincstar") || result.accountName.contains("Államkincstár"))
        assertDecimalEqual(repeated.asset.balance, result.asset.balance)
        XCTAssertEqual(repeated.positions, result.positions)
    }

    func testStateTreasuryDetailedColumnsAreKeptAndInvestmentValueIsNotConfused() throws {
        let text = """
        Államkincstár export;Megjegyzés
        Állampapír táblázat;2026.08.23
        Megnevezés;ISIN;Névérték;Jelenlegi érték;Befizetés értéke;Lejárat;Kamat
        PMÁP 2032/I;HU0000401234;1000000;1 025 000,00 HUF;950 000,00 HUF;2032.05.24.;6,50%
        """

        let result = try StateTreasuryImporter.import(text: text, accountHint: "mak.csv")
        let position = try XCTUnwrap(result.positionDetails.first)

        XCTAssertEqual(result.positions, 1)
        XCTAssertEqual(position.isin, "HU0000401234")
        XCTAssertEqual(position.nominalValue, Decimal(1_000_000))
        XCTAssertEqual(position.currentValueHUF, Decimal(1_025_000))
        XCTAssertEqual(position.investedValueHUF, Decimal(950_000))
        XCTAssertNotNil(position.maturityDate)
        XCTAssertEqual(position.couponPct, Decimal(string: "6.50"))
    }

    func testCryptoExportIsReadOnlyAndUsesHUFValueWithoutInventingFX() throws {
        let text = """
        Binance portfolio export
        Asset;Asset name;Quantity;Current value (HUF);Cost basis (HUF);As of
        BTC;Bitcoin;0,025;720 000 HUF;600 000 HUF;2026-08-30
        ETH;Ethereum;0,40;420 000 HUF;400 000 HUF;2026-08-30
        Total;Total; ;1 140 000 HUF;1 000 000 HUF;2026-08-30
        """

        XCTAssertTrue(CryptoImporter.detect(text: text, fileName: "binance-wallet.csv"))
        let result = try CryptoImporter.import(text: text, accountHint: "binance-wallet.csv")
        XCTAssertEqual(result.account, "crypto-binance")
        XCTAssertEqual(result.positions.count, 2)
        XCTAssertEqual(result.positions.map(\.symbol), ["BTC", "ETH"])
        let importedTotal = result.positions.reduce(Decimal(0)) { $0 + $1.currentValueHUF }
        XCTAssertEqual(importedTotal, Decimal(1_140_000))
        XCTAssertTrue(result.warnings.first?.contains("Csak olvasható") == true)
    }
}
