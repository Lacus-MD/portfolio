import Foundation
import XCTest
@testable import Portfolio

final class ReconciliationTests: XCTestCase {
    func testSeverityOrderingKeepsCriticalIssuesFirst() {
        XCTAssertTrue(ReconciliationSeverity.critical > .warning)
        XCTAssertTrue(ReconciliationSeverity.warning > .notice)
        XCTAssertTrue(ReconciliationSeverity.notice > .clear)

        let issues = [
            ReconciliationIssue(id: "notice", severity: .notice,
                                title: "Tájékoztató", detail: "Rendben"),
            ReconciliationIssue(id: "critical", severity: .critical,
                                title: "Hiányzik", detail: "Ellenőrizd")
        ]
        let report = ReconciliationReport(generatedAt: Date(), rows: [], issues: issues)
        XCTAssertEqual(report.severity, .critical)
        XCTAssertFalse(report.isClear)
    }

    func testClearReportHasNoImplicitWarning() {
        let row = ReconciliationRow(id: "otp", platformName: "OTP",
                                    source: "Helyi import", valueHUF: 631_729,
                                    depositsHUF: 631_729, changeHUF: 0,
                                    severity: .clear, detail: "Rendben")
        let report = ReconciliationReport(generatedAt: Date(), rows: [row], issues: [])
        XCTAssertEqual(report.severity, .clear)
        XCTAssertTrue(report.isClear)
    }

    func testReportRoundTripPreservesStableRowIDs() throws {
        let row = ReconciliationRow(id: "treasury-allamkincstar",
                                    platformName: "Államkincstár",
                                    source: "WebKincstár export",
                                    valueHUF: 1_234_567,
                                    depositsHUF: 1_000_000,
                                    changeHUF: 234_567,
                                    severity: .warning,
                                    detail: "Régi export")
        let report = ReconciliationReport(generatedAt: Date(timeIntervalSince1970: 10),
                                          rows: [row], issues: [])
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(ReconciliationReport.self, from: data)
        XCTAssertEqual(decoded.rows.map(\.id), ["treasury-allamkincstar"])
        XCTAssertEqual(decoded.rows.first?.valueHUF, Decimal(1_234_567))
        XCTAssertEqual(decoded.rows.first?.severity, .warning)
    }
}
