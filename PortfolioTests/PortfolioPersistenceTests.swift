import Foundation
import XCTest
@testable import Portfolio

final class PortfolioPersistenceTests: XCTestCase {
    func testPayloadRoundTripPreservesExtendedFieldsAndSchemaVersion() throws {
        var payload = PortfolioFile.Payload()
        payload.holdings = [Holding(account: "broker", isin: "IE00BK5BQT80", ticker: "VWCE",
                                    name: "VWCE", quantity: 2, averageCost: 100,
                                    tbszYear: 2026, costHUF: 80_000)]
        payload.cash = ["broker": ["EUR": 12.5]]
        payload.conversionSpread = ["broker": Decimal(string: "0.01")!]
        payload.hiddenNews = ["https://example.test/news"]
        payload.themeID = "monochrome-red"
        payload.allocationTargets = ["broker": 80]
        payload.platformOrder = ["broker"]

        let data = try JSONEncoder().encode(payload)
        let decoded = try PortfolioFile.decodePayload(data)

        XCTAssertEqual(decoded.schemaVersion, PortfolioFile.currentSchemaVersion)
        XCTAssertEqual(decoded.holdings.count, 1)
        XCTAssertEqual(decoded.cash["broker"]?["EUR"], Decimal(string: "12.5"))
        XCTAssertEqual(decoded.conversionSpread["broker"], Decimal(string: "0.01"))
        XCTAssertEqual(decoded.hiddenNews, payload.hiddenNews)
        XCTAssertEqual(decoded.themeID, payload.themeID)
        XCTAssertEqual(decoded.allocationTargets, payload.allocationTargets)
        XCTAssertEqual(decoded.platformOrder, payload.platformOrder)
    }

    func testUnversionedBuild20PayloadIsExplicitlyUpgraded() throws {
        let legacy = try JSONSerialization.data(withJSONObject: [
            "holdings": [],
            "snapshots": [],
            "deposits": [],
            "fees": []
        ])

        let decoded = try PortfolioFile.decodePayload(legacy)
        XCTAssertEqual(decoded.schemaVersion, PortfolioFile.currentSchemaVersion)
        XCTAssertTrue(decoded.holdings.isEmpty)
    }

    func testInjectedStorageRecoversCorruptMainWithoutLosingBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfolio-storage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = PortfolioFile.Storage(
            mainURL: root.appendingPathComponent("portfolio.json"),
            backupURL: root.appendingPathComponent("portfolio.backup.json")
        )
        var payload = PortfolioFile.Payload()
        payload.holdings = [Holding(account: "broker", isin: "IE00BK5BQT80", ticker: "VWCE",
                                    name: "VWCE", quantity: 1, averageCost: 100,
                                    tbszYear: 2026)]
        try storage.save(payload)
        try Data("broken".utf8).write(to: storage.mainURL, options: .atomic)

        let loaded = storage.loadDetailed()
        if case .recovered = loaded.status {
            // expected
        } else {
            XCTFail("Expected backup recovery")
        }
        XCTAssertEqual(loaded.payload.holdings.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("portfolio.broken.json").path
        ))
    }

    func testInjectedBackupCipherRoundTripsAndRejectsTampering() throws {
        let cipher = BackupCipher(keyData: Data(repeating: 7, count: 32))
        var payload = PortfolioFile.Payload()
        payload.themeID = "monochrome-yellow"
        payload.fxRate = 401.25

        let encrypted = try cipher.encrypt(payload)
        let decrypted = try cipher.decrypt(encrypted)
        XCTAssertEqual(decrypted.themeID, payload.themeID)
        XCTAssertEqual(decrypted.fxRate, payload.fxRate)

        var tampered = encrypted
        tampered[tampered.index(before: tampered.endIndex)] ^= 0xFF
        XCTAssertThrowsError(try cipher.decrypt(tampered))
    }
}
