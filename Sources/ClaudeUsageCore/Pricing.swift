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
