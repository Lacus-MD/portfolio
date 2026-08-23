import os

/// Lightweight signposts for Instruments and XCTest performance metrics.
enum PerformanceSignposts {
    static let log = OSLog(subsystem: "hu.halasz.portfolio", category: "performance")

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
