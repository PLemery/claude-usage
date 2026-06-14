import XCTest
@testable import ClaudeUsageCore

final class CostEstimatorTests: XCTestCase {
    func testPricesEachTokenTypeByModel() {
        // sonnet: 1_000_000 input @ $3, 1_000_000 output @ $15, cacheRead 1_000_000 @ $0.30
        let turn = TranscriptTurn(model: "claude-sonnet-4-6",
                                  usage: TokenUsage(input: 1_000_000, output: 1_000_000, cacheCreation: 0, cacheRead: 1_000_000),
                                  timestamp: Date())
        XCTAssertEqual(CostEstimator.costUSD(of: [turn]), 3 + 15 + 0.30, accuracy: 0.0001)
    }

    func testSyntheticIsFree() {
        let turn = TranscriptTurn(model: "<synthetic>",
                                  usage: TokenUsage(input: 1_000_000, output: 1_000_000),
                                  timestamp: Date())
        XCTAssertEqual(CostEstimator.costUSD(of: [turn]), 0, accuracy: 0.0001)
    }
}
