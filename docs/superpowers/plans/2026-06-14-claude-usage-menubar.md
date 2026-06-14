# Claude Usage Menu Bar App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu-bar app that shows the current 5-hour Claude usage % and, on click, a popover with 5-hour/7-day limits, current chat context size, and per-project token/cost totals.

**Architecture:** A Swift Package with a testable core library (`ClaudeUsageCore`) holding all pure logic — JSONL parsing, context %, cost estimation, project aggregation, Keychain access, and the usage-API client — plus a thin SwiftUI executable (`ClaudeUsageApp`) that renders `MenuBarExtra` and wires the core to the UI. Two independent data sources (network usage API + local JSONL files) keep failures isolated.

**Tech Stack:** Swift 5.9+, Swift Package Manager, SwiftUI `MenuBarExtra`, XCTest, macOS 13+ (dev machine macOS 26). No third-party dependencies.

---

## File Structure

```
Claude Usage/
├── Package.swift
├── Sources/
│   ├── ClaudeUsageCore/                 # testable library, no UI
│   │   ├── Models.swift                 # data structs
│   │   ├── Pricing.swift                # per-model price table
│   │   ├── JSONLParser.swift            # one transcript file → tokens/model/time
│   │   ├── ContextCalculator.swift      # latest turn → context %
│   │   ├── CostEstimator.swift          # tokens × price
│   │   ├── LocalStats.swift             # aggregate ~/.claude/projects
│   │   ├── KeychainReader.swift         # read OAuth token
│   │   └── UsageAPIClient.swift         # call usage endpoint
│   └── ClaudeUsageApp/                  # thin SwiftUI app
│       ├── ClaudeUsageApp.swift         # @main, MenuBarExtra, .accessory policy
│       ├── AppViewModel.swift           # orchestrates core + refresh timer
│       ├── MenuBarLabel.swift           # the % text + color
│       └── UsagePopover.swift           # the dropdown UI
└── Tests/
    └── ClaudeUsageCoreTests/
        ├── Fixtures/sample-session.jsonl
        ├── JSONLParserTests.swift
        ├── ContextCalculatorTests.swift
        ├── CostEstimatorTests.swift
        └── LocalStatsTests.swift
```

**Design note:** All logic that can be tested without a screen or network lives in `ClaudeUsageCore` and is covered by `swift test`. The app target is deliberately thin (wiring only) because SwiftUI views and live network/Keychain calls are verified by running the app, not by unit tests.

---

## Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeUsageCore/Models.swift` (placeholder type so the target compiles)
- Create: `Sources/ClaudeUsageApp/ClaudeUsageApp.swift` (minimal app)
- Create: `Tests/ClaudeUsageCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeUsageCore"),
        .executableTarget(
            name: "ClaudeUsageApp",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Add a placeholder core type so the library compiles**

`Sources/ClaudeUsageCore/Models.swift`:

```swift
import Foundation

/// Marker so the target has at least one symbol. Real models added in Task 4.
public enum ClaudeUsageCore {
    public static let contextWindowTokens = 200_000
}
```

- [ ] **Step 3: Add a minimal app entry point**

`Sources/ClaudeUsageApp/ClaudeUsageApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeUsageApp: App {
    var body: some Scene {
        MenuBarExtra("…", systemImage: "gauge.medium") {
            Text("Hello from the menu bar")
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 4: Add a smoke test**

`Tests/ClaudeUsageCoreTests/SmokeTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageCore

final class SmokeTests: XCTestCase {
    func testContextWindowConstant() {
        XCTAssertEqual(ClaudeUsageCore.contextWindowTokens, 200_000)
    }
}
```

- [ ] **Step 5: Create the empty fixtures dir so the resource copy succeeds**

Run: `mkdir -p "Tests/ClaudeUsageCoreTests/Fixtures"` then `touch "Tests/ClaudeUsageCoreTests/Fixtures/.gitkeep"`

- [ ] **Step 6: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; 1 test passes.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: scaffold ClaudeUsage swift package"
```

---

## Task 2: Spike — confirm the usage API endpoint

This is an **investigation**, not TDD. Goal: learn whether we can get exact limits, and how. Time-box ~20 minutes. Record findings in the plan's commit message.

- [ ] **Step 1: Find the endpoint Claude Code itself uses**

The Claude Code CLI calls the usage endpoint for its `/usage` command. Grep the installed CLI for the URL.

Run:
```bash
CLI=$(node -e "console.log(require.resolve('@anthropic-ai/claude-code/cli.js'))" 2>/dev/null || find /usr/local /opt/homebrew "$HOME/.npm" "$HOME/.nvm" -name cli.js -path '*claude-code*' 2>/dev/null | head -1)
echo "CLI: $CLI"
grep -oE 'https://[a-zA-Z0-9./_-]*usage[a-zA-Z0-9./_-]*' "$CLI" | sort -u
grep -oE '"/[a-z0-9/_-]*usage[a-z0-9/_-]*"' "$CLI" | sort -u
```
Expected: one or more candidate paths (e.g. an `/api/.../usage` path on `api.anthropic.com` or `console.anthropic.com`). Record them.

- [ ] **Step 2: Read the OAuth token from the Keychain (do not paste it anywhere)**

Run:
```bash
security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import json,sys; d=json.load(sys.stdin); print('keys:', list(d.keys()))"
```
Expected: prints the JSON keys (e.g. `claudeAiOauth` → `accessToken`, `refreshToken`, `expiresAt`, `scopes`). Note the exact path to the access token.

- [ ] **Step 3: Probe the candidate endpoint**

Using the path(s) from Step 1 and the token path from Step 2:
```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import json,sys; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -sS -o /tmp/usage.json -w "HTTP %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "<CANDIDATE_URL_FROM_STEP_1>"
python3 -m json.tool < /tmp/usage.json | head -60
```
Expected: HTTP 200 and a JSON body containing 5-hour / 7-day utilization and reset times.

- [ ] **Step 4: Record the result and decide the mode**

- If 200 with usable data → **exact mode**: capture the response shape into `/tmp/usage.json` for Task 8's decoder. Note the exact JSON field names for the two windows and their reset timestamps.
- If 401/403/404 → **estimate mode**: Task 8 becomes a local estimator instead (documented in that task's fallback). Everything else in the plan is unchanged.
- **Also scan the response for a credit/wallet balance** (extra-usage funds). Run:
  `python3 -c "import json; d=json.load(open('/tmp/usage.json')); print([k for k in str(d).split() if any(w in k.lower() for w in ('credit','balance','wallet','funds','amount'))][:20])"`
  and eyeball `/tmp/usage.json` for a dollar/credit field. If none, try a sibling billing path (e.g. swap `usage` → `balance`/`credits`/`billing` in the URL from Step 1). Record the field path (or "no wallet field exposed") — this drives the optional wallet row in Tasks 8 & 10.

- [ ] **Step 5: Commit the finding**

```bash
git commit --allow-empty -m "spike: usage endpoint = <URL or 'unavailable -> estimate mode'>, fields = <...>"
```

---

## Task 3: Core models

**Files:**
- Modify: `Sources/ClaudeUsageCore/Models.swift`

- [ ] **Step 1: Replace Models.swift with the real types**

```swift
import Foundation

public enum ClaudeUsageCore {
    public static let contextWindowTokens = 200_000
}

/// Token counts from one assistant turn's `usage` object.
public struct TokenUsage: Equatable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input; self.output = output
        self.cacheCreation = cacheCreation; self.cacheRead = cacheRead
    }

    /// Every token billed across this turn (used for project burn totals).
    public var total: Int { input + output + cacheCreation + cacheRead }

    public static func + (l: TokenUsage, r: TokenUsage) -> TokenUsage {
        TokenUsage(input: l.input + r.input, output: l.output + r.output,
                   cacheCreation: l.cacheCreation + r.cacheCreation, cacheRead: l.cacheRead + r.cacheRead)
    }
}

/// One assistant message extracted from a transcript.
public struct TranscriptTurn: Equatable {
    public var model: String
    public var usage: TokenUsage
    public var timestamp: Date
    public init(model: String, usage: TokenUsage, timestamp: Date) {
        self.model = model; self.usage = usage; self.timestamp = timestamp
    }
}

/// Aggregated usage for one project folder.
public struct ProjectUsage: Equatable {
    public var name: String
    public var usage: TokenUsage
    public var estimatedCostUSD: Double
    public init(name: String, usage: TokenUsage, estimatedCostUSD: Double) {
        self.name = name; self.usage = usage; self.estimatedCostUSD = estimatedCostUSD
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeUsageCore/Models.swift
git commit -m "feat: add core usage models"
```

---

## Task 4: JSONL parser (TDD)

**Files:**
- Create: `Tests/ClaudeUsageCoreTests/Fixtures/sample-session.jsonl`
- Create: `Tests/ClaudeUsageCoreTests/JSONLParserTests.swift`
- Create: `Sources/ClaudeUsageCore/JSONLParser.swift`

- [ ] **Step 1: Create the fixture (two assistant turns + noise lines)**

`Tests/ClaudeUsageCoreTests/Fixtures/sample-session.jsonl`:

```
{"type":"permission-mode","permissionMode":"default"}
{"type":"assistant","timestamp":"2026-04-11T17:30:00.000Z","sessionId":"s1","cwd":"/Users/me/Documents/Projects/Reminders","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":5,"cache_read_input_tokens":1000}}}
{"type":"user","timestamp":"2026-04-11T17:31:00.000Z","message":{"role":"user","content":"hi"}}
{"type":"assistant","timestamp":"2026-04-11T17:32:33.357Z","sessionId":"s1","cwd":"/Users/me/Documents/Projects/Reminders","message":{"role":"assistant","model":"claude-sonnet-4-6","usage":{"input_tokens":3,"output_tokens":184,"cache_creation_input_tokens":127,"cache_read_input_tokens":93489}}}
{"type":"assistant","timestamp":"2026-04-11T17:33:00.000Z","message":{"role":"assistant","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
```

- [ ] **Step 2: Write the failing test**

`Tests/ClaudeUsageCoreTests/JSONLParserTests.swift`:

```swift
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
```

- [ ] **Step 3: Run — verify it fails**

Run: `swift test --filter JSONLParserTests`
Expected: FAIL — `JSONLParser` is undefined.

- [ ] **Step 4: Implement the parser**

`Sources/ClaudeUsageCore/JSONLParser.swift`:

```swift
import Foundation

public enum JSONLParser {
    private struct Line: Decodable {
        let type: String?
        let timestamp: Date?
        let message: Message?
        struct Message: Decodable {
            let model: String?
            let usage: Usage?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    /// Returns assistant turns (in file order) that carry a usage object.
    public static func parse(fileAt url: URL) throws -> [TranscriptTurn] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        var turns: [TranscriptTurn] = []
        for raw in data.split(separator: UInt8(ascii: "\n")) where !raw.isEmpty {
            guard let line = try? decoder.decode(Line.self, from: Data(raw)),
                  line.type == "assistant",
                  let msg = line.message, let usage = msg.usage else { continue }
            turns.append(TranscriptTurn(
                model: msg.model ?? "unknown",
                usage: TokenUsage(
                    input: usage.input_tokens ?? 0,
                    output: usage.output_tokens ?? 0,
                    cacheCreation: usage.cache_creation_input_tokens ?? 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0),
                timestamp: line.timestamp ?? .distantPast))
        }
        return turns
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// ISO-8601 with fractional seconds (e.g. 2026-04-11T17:32:33.357Z).
    static let iso8601WithFractionalSeconds = custom { decoder in
        let s = try decoder.singleValueContainer().decode(String.self)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date: \(s)"))
    }
}
```

- [ ] **Step 5: Run — verify it passes**

Run: `swift test --filter JSONLParserTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsageCore/JSONLParser.swift Tests/ClaudeUsageCoreTests/JSONLParserTests.swift Tests/ClaudeUsageCoreTests/Fixtures/sample-session.jsonl
git commit -m "feat: parse Claude transcript JSONL into typed turns"
```

---

## Task 5: Context calculator (TDD)

Context size = the latest turn's input side ÷ window. Output tokens are excluded.

**Files:**
- Create: `Tests/ClaudeUsageCoreTests/ContextCalculatorTests.swift`
- Create: `Sources/ClaudeUsageCore/ContextCalculator.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run — verify it fails**

Run: `swift test --filter ContextCalculatorTests`
Expected: FAIL — `ContextCalculator` undefined.

- [ ] **Step 3: Implement**

`Sources/ClaudeUsageCore/ContextCalculator.swift`:

```swift
import Foundation

public enum ContextCalculator {
    /// Input-side tokens of the most recent turn (what occupies the context window).
    public static func usedTokens(in turns: [TranscriptTurn]) -> Int {
        guard let last = turns.max(by: { $0.timestamp < $1.timestamp }) else { return 0 }
        return last.usage.input + last.usage.cacheCreation + last.usage.cacheRead
    }

    public static func fraction(in turns: [TranscriptTurn], window: Int) -> Double {
        guard window > 0 else { return 0 }
        return Double(usedTokens(in: turns)) / Double(window)
    }
}
```

- [ ] **Step 4: Run — verify it passes**

Run: `swift test --filter ContextCalculatorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsageCore/ContextCalculator.swift Tests/ClaudeUsageCoreTests/ContextCalculatorTests.swift
git commit -m "feat: compute current-session context fraction"
```

---

## Task 6: Pricing + cost estimator (TDD)

**Files:**
- Create: `Sources/ClaudeUsageCore/Pricing.swift`
- Create: `Tests/ClaudeUsageCoreTests/CostEstimatorTests.swift`
- Create: `Sources/ClaudeUsageCore/CostEstimator.swift`

- [ ] **Step 1: Write the pricing table**

`Sources/ClaudeUsageCore/Pricing.swift`:

```swift
import Foundation

/// USD per 1,000,000 tokens. Approximate public list prices — clearly an ESTIMATE.
/// Edit these if prices change.
public struct ModelPrice {
    public let input: Double
    public let output: Double
    public let cacheWrite: Double
    public let cacheRead: Double
}

public enum Pricing {
    public static let opus  = ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50)
    public static let sonnet = ModelPrice(input: 3,  output: 15, cacheWrite: 3.75,  cacheRead: 0.30)
    public static let haiku = ModelPrice(input: 0.80, output: 4, cacheWrite: 1.00,  cacheRead: 0.08)

    /// Map a transcript model string to a price. Synthetic/unknown → nil (free).
    public static func price(for model: String) -> ModelPrice? {
        let m = model.lowercased()
        if m.contains("synthetic") { return nil }
        if m.contains("opus") { return opus }
        if m.contains("haiku") { return haiku }
        if m.contains("sonnet") { return sonnet }
        return sonnet // sensible default for unrecognised real models
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/ClaudeUsageCoreTests/CostEstimatorTests.swift`:

```swift
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
```

- [ ] **Step 3: Run — verify it fails**

Run: `swift test --filter CostEstimatorTests`
Expected: FAIL — `CostEstimator` undefined.

- [ ] **Step 4: Implement**

`Sources/ClaudeUsageCore/CostEstimator.swift`:

```swift
import Foundation

public enum CostEstimator {
    public static func costUSD(of turns: [TranscriptTurn]) -> Double {
        turns.reduce(0) { acc, turn in
            guard let p = Pricing.price(for: turn.model) else { return acc }
            let u = turn.usage
            let perMillion =
                Double(u.input) * p.input +
                Double(u.output) * p.output +
                Double(u.cacheCreation) * p.cacheWrite +
                Double(u.cacheRead) * p.cacheRead
            return acc + perMillion / 1_000_000.0
        }
    }
}
```

- [ ] **Step 5: Run — verify it passes**

Run: `swift test --filter CostEstimatorTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeUsageCore/Pricing.swift Sources/ClaudeUsageCore/CostEstimator.swift Tests/ClaudeUsageCoreTests/CostEstimatorTests.swift
git commit -m "feat: estimate cost per model and token type"
```

---

## Task 7: Local stats aggregation (TDD)

Walk `~/.claude/projects/<folder>/*.jsonl`, group by project, rank by tokens, and find the most-recent session for context. Project name comes from the `cwd`'s last path component (fallback: folder name).

**Files:**
- Create: `Tests/ClaudeUsageCoreTests/LocalStatsTests.swift`
- Create: `Sources/ClaudeUsageCore/LocalStats.swift`

- [ ] **Step 1: Write the failing test (builds a temp project tree)**

```swift
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
```

- [ ] **Step 2: Run — verify it fails**

Run: `swift test --filter LocalStatsTests`
Expected: FAIL — `LocalStats` undefined.

- [ ] **Step 3: Implement**

`Sources/ClaudeUsageCore/LocalStats.swift`:

```swift
import Foundation

public struct LocalStatsResult: Equatable {
    public var projects: [ProjectUsage]      // ranked by total tokens, descending
    public var currentContextTokens: Int     // input side of newest turn across all sessions
}

public enum LocalStats {
    /// Default location of Claude Code transcripts.
    public static func defaultProjectsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    public static func scan(projectsRoot: URL) throws -> LocalStatsResult {
        let fm = FileManager.default
        var projects: [ProjectUsage] = []
        var newest: TranscriptTurn?

        let folders = (try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            var folderUsage = TokenUsage()
            var folderTurns: [TranscriptTurn] = []
            var projectName = folder.lastPathComponent

            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let turns = (try? JSONLParser.parse(fileAt: file)) ?? []
                folderTurns += turns
                for t in turns {
                    folderUsage = folderUsage + t.usage
                    if let n = newest { if t.timestamp > n.timestamp { newest = t } } else { newest = t }
                }
            }
            if folderUsage.total == 0 { continue }
            // Prefer the human project name from cwd if available.
            if let cwd = lastCwd(in: folder) { projectName = (cwd as NSString).lastPathComponent }
            projects.append(ProjectUsage(name: projectName, usage: folderUsage,
                                         estimatedCostUSD: CostEstimator.costUSD(of: folderTurns)))
        }

        projects.sort { $0.usage.total > $1.usage.total }
        let contextTokens = newest.map { $0.usage.input + $0.usage.cacheCreation + $0.usage.cacheRead } ?? 0
        return LocalStatsResult(projects: projects, currentContextTokens: contextTokens)
    }

    /// Reads the `cwd` of the last assistant line in a folder, for a friendly project name.
    private static func lastCwd(in folder: URL) -> String? {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        guard let newestFile = files.filter({ $0.pathExtension == "jsonl" })
            .max(by: { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da < db
            }),
            let text = try? String(contentsOf: newestFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cwd = obj["cwd"] as? String { return cwd }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run — verify it passes**

Run: `swift test --filter LocalStatsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsageCore/LocalStats.swift Tests/ClaudeUsageCoreTests/LocalStatsTests.swift
git commit -m "feat: aggregate per-project usage and current context from disk"
```

---

## Task 8: Keychain reader + usage API client

**Spike result: EXACT MODE confirmed.** The endpoint, headers, and JSON shape below are real (verified HTTP 200 in Task 2). The estimate-mode fallback is retained only for resilience if the endpoint ever changes.

The live `fetch()` (network/Keychain) is verified by running on the real machine, but `decode()` is now **unit-testable** against `Fixtures/usage-response.json` — write that test first (TDD): assert `fiveHour.fraction == 0.18`, `sevenDay.fraction == 0.02`, `wallet.used == 8.09`, `wallet.limit == 20.0`, `wallet.isEnabled == true`. The `decode` and `parseDate` methods are `static` and `internal`, reachable from tests via `@testable import`.

**Files:**
- Create: `Sources/ClaudeUsageCore/KeychainReader.swift`
- Create: `Sources/ClaudeUsageCore/UsageAPIClient.swift`

- [ ] **Step 1: Implement the Keychain reader**

`Sources/ClaudeUsageCore/KeychainReader.swift`:

```swift
import Foundation
import Security

public enum KeychainReader {
    /// Reads the Claude Code OAuth access token from the login Keychain.
    /// Returns nil if not signed in.
    public static func claudeAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Shape confirmed in Task 2 Step 2; adjust the key path to match the spike.
        let oauth = json["claudeAiOauth"] as? [String: Any]
        return oauth?["accessToken"] as? String
    }
}
```

> If the Task 2 spike showed a different JSON shape, change the key path on the last two lines to match what it printed.

- [ ] **Step 2 (EXACT MODE): Implement the usage client**

Use the URL and field names recorded in Task 2. `UsageSnapshot` is the UI-facing type.

`Sources/ClaudeUsageCore/UsageAPIClient.swift`:

```swift
import Foundation

public struct LimitWindow: Equatable {
    public var fraction: Double      // 0.0–1.0 utilization
    public var resetsAt: Date
    public init(fraction: Double, resetsAt: Date) { self.fraction = fraction; self.resetsAt = resetsAt }
}

/// Extra-usage ("wallet") balance from the API's `extra_usage` object.
/// `used`/`limit` are stored in whole currency units (the API returns minor units
/// i.e. cents, so the decoder divides by 100).
public struct Wallet: Equatable {
    public var isEnabled: Bool
    public var used: Double          // currency units, e.g. dollars
    public var limit: Double         // currency units
    public var utilization: Double   // 0.0–1.0
    public var currency: String
    public var remaining: Double { max(limit - used, 0) }
    public init(isEnabled: Bool, used: Double, limit: Double, utilization: Double, currency: String) {
        self.isEnabled = isEnabled; self.used = used; self.limit = limit
        self.utilization = utilization; self.currency = currency
    }
}

public struct UsageSnapshot: Equatable {
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var wallet: Wallet?        // extra-usage balance, if exposed
    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?, wallet: Wallet? = nil) {
        self.fiveHour = fiveHour; self.sevenDay = sevenDay; self.wallet = wallet
    }
}

public enum UsageAPIError: Error { case notSignedIn, badStatus(Int), decode }

public enum UsageAPIClient {
    /// Endpoint + headers confirmed by the Task 2 spike (HTTP 200).
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func fetch(session: URLSession = .shared) async throws -> UsageSnapshot {
        guard let token = KeychainReader.claudeAccessToken() else { throw UsageAPIError.notSignedIn }
        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")        // REQUIRED — 401 without it
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("ClaudeUsage/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UsageAPIError.badStatus(-1) }
        guard http.statusCode == 200 else { throw UsageAPIError.badStatus(http.statusCode) }
        return try decode(data)
    }

    /// Real `/api/oauth/usage` shape (see Fixtures/usage-response.json):
    ///   { five_hour: {utilization: 0-100, resets_at: ISO8601},
    ///     seven_day: {...},
    ///     extra_usage: {is_enabled, monthly_limit, used_credits, utilization, currency} }
    /// `utilization` is a 0–100 percent; minor units (cents) for credits.
    static func decode(_ data: Data) throws -> UsageSnapshot {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.decode
        }
        func window(_ key: String) -> LimitWindow? {
            guard let w = obj[key] as? [String: Any],
                  let util = w["utilization"] as? Double,
                  let resetStr = w["resets_at"] as? String,
                  let reset = parseDate(resetStr) else { return nil }
            return LimitWindow(fraction: util / 100.0, resetsAt: reset)
        }
        var wallet: Wallet?
        if let e = obj["extra_usage"] as? [String: Any] {
            let used = (e["used_credits"] as? Double) ?? 0
            let limit = (e["monthly_limit"] as? Double) ?? Double(e["monthly_limit"] as? Int ?? 0)
            let util = (e["utilization"] as? Double) ?? 0
            wallet = Wallet(
                isEnabled: (e["is_enabled"] as? Bool) ?? false,
                used: used / 100.0,            // minor units → currency units
                limit: limit / 100.0,
                utilization: util / 100.0,
                currency: (e["currency"] as? String) ?? "USD")
        }
        return UsageSnapshot(fiveHour: window("five_hour"), sevenDay: window("seven_day"), wallet: wallet)
    }

    /// `resets_at` carries fractional seconds and a +00:00 offset.
    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
```

- [ ] **Step 2 (ESTIMATE MODE — only if spike failed): replace `fetch` body**

If the spike returned no usable endpoint, implement `fetch` to estimate from local data instead, and leave `endpoint` unused:

```swift
public static func fetch(session: URLSession = .shared) async throws -> UsageSnapshot {
    // Estimate 5h/7d from local token burn in the trailing window.
    let root = LocalStats.defaultProjectsRoot()
    let stats = try LocalStats.scan(projectsRoot: root)
    // Without the plan's true ceiling these are rough; surface as "~est" in the UI.
    // Use a conservative assumed 5h ceiling; refine once a real number is known.
    let assumedFiveHourTokenCeiling = 5_000_000.0
    let recent = Double(stats.projects.reduce(0) { $0 + $1.usage.total })
    let frac = min(recent / assumedFiveHourTokenCeiling, 1.0)
    let reset = Date().addingTimeInterval(5 * 3600)
    return UsageSnapshot(fiveHour: LimitWindow(fraction: frac, resetsAt: reset), sevenDay: nil)
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 4: Manually verify against the real machine**

Add a temporary `main`-style check or use `swift test` with an integration test gated by an env var. Simplest: run the app (Task 10) and confirm a real % appears. For now:

Run: `swift build` then in a scratch test print the result:
```bash
swift test --filter Smoke 2>/dev/null; echo "manual check happens in Task 10"
```
Expected: builds; live verification deferred to Task 10 where the UI shows the number.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsageCore/KeychainReader.swift Sources/ClaudeUsageCore/UsageAPIClient.swift
git commit -m "feat: read Keychain token and fetch usage limits"
```

---

## Task 9: App view model (orchestration)

Combines both data sources into observable state and refreshes on a timer. Pure-enough to unit-test the colour logic.

**Files:**
- Create: `Sources/ClaudeUsageApp/AppViewModel.swift`
- Create: `Tests/ClaudeUsageCoreTests/MenuBarColorTests.swift` (tests a core helper)
- Create: `Sources/ClaudeUsageCore/UsageLevel.swift`

- [ ] **Step 1: Write the failing test for the colour thresholds**

`Tests/ClaudeUsageCoreTests/MenuBarColorTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageCore

final class MenuBarColorTests: XCTestCase {
    func testThresholds() {
        XCTAssertEqual(UsageLevel.level(for: 0.10), .ok)
        XCTAssertEqual(UsageLevel.level(for: 0.70), .warn)
        XCTAssertEqual(UsageLevel.level(for: 0.95), .critical)
    }
}
```

- [ ] **Step 2: Run — verify it fails**

Run: `swift test --filter MenuBarColorTests`
Expected: FAIL — `UsageLevel` undefined.

- [ ] **Step 3: Implement the level helper**

`Sources/ClaudeUsageCore/UsageLevel.swift`:

```swift
import Foundation

public enum UsageLevel: Equatable {
    case ok, warn, critical
    /// green < 0.6 ≤ amber < 0.9 ≤ red
    public static func level(for fraction: Double) -> UsageLevel {
        if fraction >= 0.9 { return .critical }
        if fraction >= 0.6 { return .warn }
        return .ok
    }
}
```

- [ ] **Step 4: Run — verify it passes**

Run: `swift test --filter MenuBarColorTests`
Expected: PASS.

- [ ] **Step 5: Implement the view model**

`Sources/ClaudeUsageApp/AppViewModel.swift`:

```swift
import Foundation
import SwiftUI
import ClaudeUsageCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var stats: LocalStatsResult?
    @Published var lastUpdated: Date?
    @Published var errorText: String?

    private var timer: Timer?

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        do { snapshot = try await UsageAPIClient.fetch(); errorText = nil }
        catch { errorText = "Limits unavailable"; }
        stats = try? LocalStats.scan(projectsRoot: LocalStats.defaultProjectsRoot())
        lastUpdated = Date()
    }

    var menuBarText: String {
        guard let f = snapshot?.fiveHour?.fraction else { return "—" }
        return "\(Int((f * 100).rounded()))%"
    }

    var menuBarColor: Color {
        switch UsageLevel.level(for: snapshot?.fiveHour?.fraction ?? 0) {
        case .ok: return .green
        case .warn: return .orange
        case .critical: return .red
        }
    }
}
```

- [ ] **Step 6: Build and test**

Run: `swift build && swift test`
Expected: all tests pass; app builds.

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeUsageCore/UsageLevel.swift Sources/ClaudeUsageApp/AppViewModel.swift Tests/ClaudeUsageCoreTests/MenuBarColorTests.swift
git commit -m "feat: app view model with colour-coded 5h level"
```

---

## Task 10: SwiftUI menu bar + popover

UI wiring; verified by running the app and looking at it.

**Files:**
- Modify: `Sources/ClaudeUsageApp/ClaudeUsageApp.swift`
- Create: `Sources/ClaudeUsageApp/MenuBarLabel.swift`
- Create: `Sources/ClaudeUsageApp/UsagePopover.swift`

- [ ] **Step 1: Menu bar label**

`Sources/ClaudeUsageApp/MenuBarLabel.swift`:

```swift
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var vm: AppViewModel
    var body: some View {
        Text(vm.menuBarText).foregroundStyle(vm.menuBarColor).monospacedDigit()
    }
}
```

- [ ] **Step 2: Popover**

`Sources/ClaudeUsageApp/UsagePopover.swift`:

```swift
import SwiftUI
import ClaudeUsageCore

struct UsagePopover: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage").font(.headline)

            window("5-Hour", vm.snapshot?.fiveHour)
            window("7-Day", vm.snapshot?.sevenDay)

            if let w = vm.snapshot?.wallet, w.isEnabled {
                Divider()
                row(title: "Extra usage",
                    trailing: "$\(String(format: "%.2f", w.used)) / $\(String(format: "%.2f", w.limit))")
                ProgressView(value: min(w.utilization, 1))
                Text("$\(String(format: "%.2f", w.remaining)) left this month")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let ctx = vm.stats?.currentContextTokens {
                Divider()
                let frac = Double(ctx) / Double(ClaudeUsageCore.contextWindowTokens)
                row(title: "Context", trailing: "\(Int((frac*100).rounded()))%")
                ProgressView(value: min(frac, 1))
            }

            if let projects = vm.stats?.projects, !projects.isEmpty {
                Divider()
                Text("Projects (~est cost)").font(.subheadline).bold()
                ForEach(projects.prefix(5), id: \.name) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text("~$\(p.estimatedCostUSD, specifier: "%.0f")").foregroundStyle(.secondary)
                        Text(format(p.usage.total)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }.font(.callout)
                }
            }

            Divider()
            HStack {
                if let t = vm.lastUpdated {
                    Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await vm.refresh() } }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private func window(_ title: String, _ w: LimitWindow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).bold()
                Spacer()
                Text(w.map { "\(Int(($0.fraction*100).rounded()))%" } ?? "—")
            }
            ProgressView(value: min(w?.fraction ?? 0, 1))
            if let w { Text("Resets \(w.resetsAt.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func row(title: String, trailing: String) -> some View {
        HStack { Text(title).bold(); Spacer(); Text(trailing) }
    }

    private func format(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1_000_000) }
        if n >= 1_000 { return "\(n/1000)K" }
        return "\(n)"
    }
}
```

- [ ] **Step 3: Wire it into the app and hide the Dock icon**

`Sources/ClaudeUsageApp/ClaudeUsageApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var vm = AppViewModel()

    var body: some Scene {
        MenuBarExtra { UsagePopover(vm: vm) }
        label: { MenuBarLabel(vm: vm) }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhaseStarted) { }
    }

    // Hide Dock icon + start refreshing once.
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private var scenePhaseStarted: Bool { vm.startOnce(); return true }
}

private extension AppViewModel {
    func startOnce() {
        struct Token { static var started = false }
        if !Token.started { Token.started = true; start() }
    }
}
```

- [ ] **Step 4: Run the app and verify by eye**

Run: `swift run ClaudeUsageApp`
Expected: a `%` appears in the menu bar (coloured); clicking it shows the popover with 5-Hour / 7-Day / Context / Projects. Confirm the 5-hour number matches Claude Code's `/usage`. Quit from the popover.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeUsageApp
git commit -m "feat: menu bar label and usage popover UI"
```

---

## Task 11: Launch at login (opt-in)

**Files:**
- Modify: `Sources/ClaudeUsageApp/UsagePopover.swift` (add a toggle)
- Create: `Sources/ClaudeUsageApp/LoginItem.swift`

- [ ] **Step 1: Implement the login-item helper**

`Sources/ClaudeUsageApp/LoginItem.swift`:

```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
        catch { /* surfaced via the toggle reverting */ }
    }
}
```

- [ ] **Step 2: Add an opt-in toggle to the popover footer**

In `UsagePopover.swift`, inside the final `VStack` (before the last `HStack`), add:

```swift
Toggle("Launch at login", isOn: Binding(
    get: { LoginItem.isEnabled },
    set: { LoginItem.set($0) }
))
.toggleStyle(.switch)
.font(.caption)
```

- [ ] **Step 3: Build and run**

Run: `swift build && swift run ClaudeUsageApp`
Expected: the popover shows a "Launch at login" switch (default off). Toggling it on registers the app.

> Note: `SMAppService` requires the app to run from a real `.app` bundle (Task 12) to fully persist; from `swift run` the toggle may not stick. That is expected — verify persistence after bundling.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeUsageApp/LoginItem.swift Sources/ClaudeUsageApp/UsagePopover.swift
git commit -m "feat: opt-in launch at login"
```

---

## Task 12: Package into a runnable .app + README

**Files:**
- Create: `scripts/make-app.sh`
- Create: `README.md`

- [ ] **Step 1: Write a bundling script**

`scripts/make-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
swift build -c release
APP="ClaudeUsage.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ClaudeUsageApp" "$APP/Contents/MacOS/ClaudeUsage"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClaudeUsage</string>
  <key>CFBundleIdentifier</key><string>com.parkerlemery.claudeusage</string>
  <key>CFBundleExecutable</key><string>ClaudeUsage</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
echo "Built $APP"
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
chmod +x scripts/make-app.sh
./scripts/make-app.sh
open ClaudeUsage.app
```
Expected: the menu bar item appears with no Dock icon; quitting and re-running confirms launch-at-login persists when toggled.

- [ ] **Step 3: Write the README**

`README.md`:

```markdown
# Claude Usage

A macOS menu-bar app showing your live Claude usage: 5-hour limit %, 7-day limit %,
current chat context size, and per-project token/cost estimates.

## Build
    ./scripts/make-app.sh
    open ClaudeUsage.app

## Move to Applications (optional)
    cp -R ClaudeUsage.app /Applications/

## Notes
- Reuses your existing Claude Code login (macOS Keychain). No separate sign-in.
- Limit %s come from Anthropic's usage endpoint (exact). If unavailable, the app
  falls back to local estimates.
- Costs are ESTIMATES (tokens × public list price), not billed amounts.
```

- [ ] **Step 4: Commit**

```bash
git add scripts/make-app.sh README.md
git commit -m "build: bundle .app and add README"
```

---

## Self-Review notes (for the implementer)

- **Spec coverage:** menu-bar 5h % (Task 9/10) · 7-day (Task 8/10) · context (Task 5/10) · per-project tokens+cost (Tasks 6,7,10) · exact-vs-estimate limits (Tasks 2,8) · wallet/extra-usage balance, best-effort (Tasks 2,8,10) · launch-at-login opt-in (Task 11) · menu-bar-only no-Dock (Task 10 init + Task 12 LSUIElement) · cost labeled "~est" (Task 10 UI) — all covered.
- **Type consistency:** `TokenUsage`, `TranscriptTurn`, `ProjectUsage`, `LocalStatsResult`, `UsageSnapshot`, `LimitWindow`, `UsageLevel` are defined once in Core and reused; `LocalStats.scan(projectsRoot:)` and `UsageAPIClient.fetch()` signatures match their call sites in `AppViewModel`.
- **Known runtime risks to verify during execution:** (1) the Task 2 spike result determines whether Task 8 ships exact or estimate mode — do Task 2 first; (2) `SMAppService` only persists from a real bundle (Task 12); (3) the usage endpoint field names in `UsageAPIClient.decode` are placeholders to be replaced with the spike's actual JSON keys.
```
