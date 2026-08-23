import Foundation
import XCTest

extension XCTestCase {
    func assertDecimalEqual(_ lhs: Decimal, _ rhs: Decimal,
                            accuracy: Decimal = 0,
                            file: StaticString = #filePath,
                            line: UInt = #line) {
        let difference = abs(lhs - rhs)
        XCTAssertLessThanOrEqual(difference, accuracy,
                                 "Expected \(lhs) to equal \(rhs) within \(accuracy)",
                                 file: file, line: line)
    }
}
