import XCTest
@testable import ClaudeUsageCore

final class MenuBarColorTests: XCTestCase {
    func testThresholds() {
        // green ≤ 75% < yellow < 90% ≤ red
        XCTAssertEqual(UsageLevel.level(for: 0.10), .ok)
        XCTAssertEqual(UsageLevel.level(for: 0.74), .ok)
        XCTAssertEqual(UsageLevel.level(for: 0.75), .warn)
        XCTAssertEqual(UsageLevel.level(for: 0.89), .warn)
        XCTAssertEqual(UsageLevel.level(for: 0.90), .critical)
        XCTAssertEqual(UsageLevel.level(for: 0.95), .critical)
    }
}
