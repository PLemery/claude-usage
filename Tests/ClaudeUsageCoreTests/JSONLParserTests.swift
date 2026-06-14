import XCTest
@testable import ClaudeUsageCore

final class JSONLParserTests: XCTestCase {
    private func fixtureURL() -> URL {
        Bundle.module.url(forResource: "sample-session", withExtension: "jsonl", subdirectory: "Fixtures")!
    }

    func testParsesOnlyAssistantTurnsWithUsage() throws {
        let turns = try JSONLParser.parse(fileAt: fixtureURL())
        XCTAssertEqual(turns.count, 3) // two real + one synthetic; non-assistant lines skipped
    }

    func testExtractsTokensAndModel() throws {
        let turns = try JSONLParser.parse(fileAt: fixtureURL())
        XCTAssertEqual(turns[1].model, "claude-sonnet-4-6")
        XCTAssertEqual(turns[1].usage, TokenUsage(input: 3, output: 184, cacheCreation: 127, cacheRead: 93489))
    }

    func testParsesTimestamp() throws {
        let turns = try JSONLParser.parse(fileAt: fixtureURL())
        XCTAssertEqual(turns[1].timestamp.timeIntervalSince1970, 1775928753.357, accuracy: 0.01)
    }
}
