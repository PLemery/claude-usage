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
