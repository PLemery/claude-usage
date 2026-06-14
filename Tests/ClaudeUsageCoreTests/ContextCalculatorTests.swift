import XCTest
@testable import ClaudeUsageCore

final class ContextCalculatorTests: XCTestCase {
    func testContextIsLatestTurnInputSide() {
        let turns = [
            TranscriptTurn(model: "sonnet", usage: TokenUsage(input: 10, output: 20, cacheCreation: 5, cacheRead: 1000), timestamp: Date(timeIntervalSince1970: 1)),
            TranscriptTurn(model: "sonnet", usage: TokenUsage(input: 3, output: 184, cacheCreation: 127, cacheRead: 93489), timestamp: Date(timeIntervalSince1970: 2)),
        ]
        // latest input side = 3 + 127 + 93489 = 93619
        XCTAssertEqual(ContextCalculator.usedTokens(in: turns), 93619)
        XCTAssertEqual(ContextCalculator.fraction(in: turns, window: 200_000), 93619.0 / 200_000.0, accuracy: 0.0001)
    }

    func testEmptyIsZero() {
        XCTAssertEqual(ContextCalculator.usedTokens(in: []), 0)
        XCTAssertEqual(ContextCalculator.fraction(in: [], window: 200_000), 0)
    }
}
