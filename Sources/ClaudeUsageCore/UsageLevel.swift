import Foundation

public enum UsageLevel: Equatable {
    case ok, warn, critical
    /// green ≤ 75% < yellow < 90% ≤ red
    public static func level(for fraction: Double) -> UsageLevel {
        if fraction >= 0.90 { return .critical }
        if fraction >= 0.75 { return .warn }
        return .ok
    }
}
