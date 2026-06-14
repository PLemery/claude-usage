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
