import XCTest
@testable import ClaudeUsageCore

final class SmokeTests: XCTestCase {
    func testContextWindowConstant() {
        XCTAssertEqual(ClaudeUsageCore.contextWindowTokens, 200_000)
    }
}
