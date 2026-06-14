import XCTest
@testable import ClaudeUsageCore

final class UsageDecodeTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = Bundle.module.url(forResource: "usage-response", withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testDecodesUsageResponseFixture() throws {
        let snapshot = try UsageAPIClient.decode(fixtureData())

        let fiveHour = try XCTUnwrap(snapshot.fiveHour)
        XCTAssertEqual(fiveHour.fraction, 0.18, accuracy: 0.0001)

        let sevenDay = try XCTUnwrap(snapshot.sevenDay)
        XCTAssertEqual(sevenDay.fraction, 0.02, accuracy: 0.0001)

        let wallet = try XCTUnwrap(snapshot.wallet)
        XCTAssertTrue(wallet.isEnabled)
        XCTAssertEqual(wallet.used, 8.09, accuracy: 0.001)
        XCTAssertEqual(wallet.limit, 20.0, accuracy: 0.001)
        XCTAssertEqual(wallet.utilization, 0.4045, accuracy: 0.0001)
    }

    func testParsesResetDates() throws {
        let snapshot = try UsageAPIClient.decode(fixtureData())
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNotNil(snapshot.sevenDay?.resetsAt)
    }
}
