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

public enum UsageAPIError: Error { case notSignedIn, badStatus(Int), decode, rateLimited(retryAfter: TimeInterval) }

public enum UsageAPIClient {
    /// Endpoint + headers confirmed by the Task 2 spike (HTTP 200).
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func fetch(accessToken: String, session: URLSession = .shared) async throws -> UsageSnapshot {
        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")        // REQUIRED — 401 without it
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("ClaudeUsage/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UsageAPIError.badStatus(-1) }
        guard http.statusCode != 429 else {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap { TimeInterval($0) }
            throw UsageAPIError.rateLimited(retryAfter: retryAfter ?? 300)
        }
        guard http.statusCode == 200 else {
            Log.write("usage HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
            throw UsageAPIError.badStatus(http.statusCode)
        }
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
    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
