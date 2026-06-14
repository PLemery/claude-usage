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
