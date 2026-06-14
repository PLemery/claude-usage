import XCTest
@testable import ClaudeUsageCore

final class MenuBarColorTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(UsageLevel.level(for: 0.10), .ok)
        XCTAssertEqual(UsageLevel.level(for: 0.70), .warn)
        XCTAssertEqual(UsageLevel.level(for: 0.95), .critical)
    }
}
