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
