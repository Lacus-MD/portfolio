import Foundation
import XCTest
@testable import Portfolio

final class ImporterFixtureTests: XCTestCase {
    func testCSVParserStripsBOMAndKeepsQuotedDelimiter() {
        let fields = StatementImporter.parse(
            line: "\u{FEFF}\"Dátum\";\"Leírás; részlet\";\"1,23\"",
            delimiter: ";"
        )

        XCTAssertEqual(fields, ["Dátum", "Leírás; részlet", "1,23"])
        assertDecimalEqual(HungarianCSV.number(fields[2]) ?? 0, Decimal(string: "1.23")!)
    }

    func testOTPAccountFixtureSeparatesCurrentAccountAndKeepsBalance() throws {
        let result = try OTPImporter.import(
            text: FixtureLoader.string(named: "otp-account", subdirectory: "OTP")
        )

        if case .account = result.kind {
            // expected
        } else {
            XCTFail("Expected an OTP current-account import")
        }
        XCTAssertEqual(result.entries.count, 2)
        assertDecimalEqual(result.opening, 1_000_000)
        assertDecimalEqual(result.closing, 1_388_290)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testOTPCreditFixtureIsNegativeDebtAndParsesQuotedText() throws {
        let result = try OTPImporter.import(
            text: FixtureLoader.string(named: "otp-credit", subdirectory: "OTP")
        )

        if case .credit = result.kind {
            // expected
        } else {
            XCTFail("Expected an OTP credit-card import")
        }
        XCTAssertEqual(result.entries.count, 1)
        assertDecimalEqual(result.closing, -650_867)
        assertDecimalEqual(result.totalDebt ?? 0, 650_867)
        XCTAssertTrue(result.entries[0].text.contains("KÁVÉ, BELVÁROS"))
    }

    func testRevolutSavingsFixtureKeepsInterestOutOfDeposits() throws {
        let result = RevolutImporter.importSavings(
            csv: try FixtureLoader.string(named: "revolut-savings", fileExtension: "csv", subdirectory: "Revolut"),
            platformID: "revolut-savings"
        )

        assertDecimalEqual(result.asset.balance, 1_000_223)
        XCTAssertEqual(result.deposits.filter(\.isInternal).count, 1)
        XCTAssertEqual(result.deposits.filter { !$0.isInternal }.count, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("kamat") })
        XCTAssertEqual(result.dailyBalances.count, 3)
    }

    func testRevolutAccountFixtureHandlesQuotedCommaAndSkipsPending() throws {
        let result = RevolutImporter.importAccount(
            csv: try FixtureLoader.string(named: "revolut-account", fileExtension: "csv", subdirectory: "Revolut"),
            platformID: "revolut-account"
        )

        assertDecimalEqual(result.asset.balance, 900)
        XCTAssertEqual(result.deposits.count, 2)
        XCTAssertTrue(result.deposits.contains { $0.isInternal && $0.amountHUF == -100 })
        XCTAssertTrue(result.warnings.contains { $0.contains("függő") })
    }

    func testStateTreasuryFixtureHandlesSemicolonAndQuotedName() throws {
        let result = try StateTreasuryImporter.import(
            text: FixtureLoader.string(named: "state-treasury", fileExtension: "csv",
                                       subdirectory: "StateTreasury"),
            accountHint: "allamkincstar-export.csv"
        )

        XCTAssertEqual(result.positions, 2)
        assertDecimalEqual(result.asset.balance, 1_234_567)
        XCTAssertEqual(result.account, "treasury-allamkincstar")
        XCTAssertTrue(result.accountName.contains("allamkincstar") || result.accountName.contains("Államkincstár"))
    }
}
