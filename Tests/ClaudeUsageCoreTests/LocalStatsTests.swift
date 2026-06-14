import XCTest
@testable import ClaudeUsageCore

final class LocalStatsTests: XCTestCase {
    private func makeTree() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let projA = root.appendingPathComponent("-Users-me-Alpha")
        let projB = root.appendingPathComponent("-Users-me-Beta")
        try FileManager.default.createDirectory(at: projA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projB, withIntermediateDirectories: true)
        // Alpha: big burn, older
        try """
        {"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/Users/me/Alpha","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100000,"output_tokens":100000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """.write(to: projA.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        // Beta: small burn, newest (this is the "current" context session)
        try """
        {"type":"assistant","timestamp":"2026-06-14T00:00:00.000Z","cwd":"/Users/me/Beta","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":50,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":150000}}}
        """.write(to: projB.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)
        return root
    }

    func testRanksProjectsByTokensDescending() throws {
        let stats = try LocalStats.scan(projectsRoot: makeTree())
        XCTAssertEqual(stats.projects.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(stats.projects[0].usage.total, 200000)
    }

    func testContextUsesMostRecentSessionAcrossAllProjects() throws {
        let stats = try LocalStats.scan(projectsRoot: makeTree())
        // newest turn is Beta's: input side = 50 + 0 + 150000 = 150050
        XCTAssertEqual(stats.currentContextTokens, 150050)
    }
}
