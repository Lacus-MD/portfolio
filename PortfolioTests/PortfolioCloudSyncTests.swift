import Foundation
import XCTest
@testable import Portfolio

final class PortfolioCloudSyncTests: XCTestCase {
    func testSyncEnvelopeRoundTripPreservesPlatformsAndPayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfolio-cloud-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        var payload = PortfolioFile.Payload()
        payload.platforms = [Platform(id: "otp", name: "OTP Folyószámla",
                                      kind: .current, accent: .mint,
                                      monogram: "OF")]
        payload.platformOrder = ["otp"]
        payload.themeID = "monochrome-orange"
        payload.cash = ["otp": ["HUF": 631_729]]

        let envelope = PortfolioCloudSync.Envelope(
            updatedAt: Date(timeIntervalSince1970: 1_735_000_000),
            deviceID: "device-a",
            payload: payload
        )
        let store = PortfolioCloudSync.FileStore(url: root.appendingPathComponent("sync.json"))
        try store.write(envelope)

        let decoded = try XCTUnwrap(try store.read())
        XCTAssertEqual(decoded.schemaVersion, PortfolioFile.currentSchemaVersion)
        XCTAssertEqual(decoded.deviceID, "device-a")
        XCTAssertEqual(decoded.payload.platforms.first?.name, "OTP Folyószámla")
        XCTAssertEqual(decoded.payload.platformOrder, ["otp"])
        XCTAssertEqual(decoded.payload.themeID, "monochrome-orange")
        XCTAssertEqual(decoded.payload.cash["otp"]?["HUF"], Decimal(631_729))
    }

    func testNewestRevisionUsesTimestampAndStableDeviceTieBreaker() {
        let payload = PortfolioFile.Payload()
        let earlier = PortfolioCloudSync.Envelope(
            updatedAt: Date(timeIntervalSince1970: 100), deviceID: "device-z", payload: payload
        )
        let later = PortfolioCloudSync.Envelope(
            updatedAt: Date(timeIntervalSince1970: 101), deviceID: "device-a", payload: payload
        )
        let tieWinner = PortfolioCloudSync.Envelope(
            updatedAt: earlier.updatedAt, deviceID: "device-z", payload: payload
        )
        let tieLoser = PortfolioCloudSync.Envelope(
            updatedAt: earlier.updatedAt, deviceID: "device-a", payload: payload
        )

        XCTAssertTrue(PortfolioCloudSync.isNewer(later, than: earlier))
        XCTAssertTrue(PortfolioCloudSync.isNewer(tieWinner, than: tieLoser))
        XCTAssertFalse(PortfolioCloudSync.isNewer(earlier, than: later))
    }

    func testMissingSyncFileReadsAsEmptyWithoutCreatingIt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-portfolio-sync-\(UUID().uuidString).json")
        let store = PortfolioCloudSync.FileStore(url: url)

        XCTAssertNil(try store.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
