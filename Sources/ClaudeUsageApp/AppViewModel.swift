import Foundation
import SwiftUI
import AppKit
import ClaudeUsageCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var stats: LocalStatsResult?
    @Published var lastUpdated: Date?
    @Published var errorText: String?

    let auth = AuthManager()
    private var timer: Timer?
    private var lastNetworkAttempt: Date?  // throttle the rate-limited usage endpoint

    /// When we may next call the usage endpoint. Persisted so quitting/relaunching
    /// during a 429 window doesn't re-poke the endpoint and reset its timer.
    private var cooldownUntil: Date? {
        get { UserDefaults.standard.object(forKey: "rateLimitedUntil") as? Date }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "rateLimitedUntil") }
            else { UserDefaults.standard.removeObject(forKey: "rateLimitedUntil") }
        }
    }

    func start() {
        auth.onAuthChange = { [weak self] in
            // A new token = a fresh per-token rate-limit bucket, so drop any
            // cooldown the old token earned and fetch right away.
            self?.cooldownUntil = nil
            self?.lastNetworkAttempt = nil
            Task { await self?.refresh() }
        }
        Task { await refresh() }
        LoginItem.promptForLaunchAtLoginIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        if let token = await auth.validAccessToken() {
            let now = Date()
            let cooling = cooldownUntil.map { now < $0 } ?? false
            // Refresh the usage limits about once a minute.
            let due = lastNetworkAttempt.map { now.timeIntervalSince($0) >= 60 } ?? true
            if !cooling && due {
                lastNetworkAttempt = now
                do {
                    snapshot = try await UsageAPIClient.fetch(accessToken: token)
                    errorText = nil; cooldownUntil = nil
                    Log.write("usage fetch OK — 5h=\(snapshot?.fiveHour?.fraction.description ?? "nil")")
                } catch UsageAPIError.rateLimited(let retryAfter) {
                    // Honor retry-after + a 5-min buffer so we never poke at the exact
                    // edge (this endpoint LENGTHENS the penalty on any request while limited).
                    let wait = min(max(retryAfter, 60) + 300, 7200)
                    errorText = "Rate limited — retries in ~\(Int(wait / 60))m"
                    cooldownUntil = now.addingTimeInterval(wait)  // keep last data meanwhile
                    Log.write("usage fetch 429 — retryAfter=\(retryAfter)s")
                } catch {
                    errorText = "Limits unavailable"
                    Log.write("usage fetch error: \(error)")
                }
            }
        } else {
            snapshot = nil          // signed out — the popover shows a sign-in prompt
            errorText = nil
            Log.write("refresh: no valid access token (signed out / token missing or refresh failed)")
        }
        // Local stats are free to refresh every tick.
        stats = try? LocalStats.scan(projectsRoot: LocalStats.defaultProjectsRoot())
        lastUpdated = Date()
    }

    var menuBarText: String {
        guard let f = snapshot?.fiveHour?.fraction else { return "—" }
        return "\(Int((f * 100).rounded()))%"
    }

    var menuBarColor: Color { Self.color(for: snapshot?.fiveHour?.fraction ?? 0) }

    /// Shared green/yellow/red mapping used by the menu-bar label and every progress bar.
    static func color(for fraction: Double) -> Color {
        switch UsageLevel.level(for: fraction) {
        case .ok: return .green
        case .warn: return .yellow
        case .critical: return .red
        }
    }

    /// AppKit equivalent, for the menu-bar number (which must be drawn as a
    /// non-template image so macOS doesn't strip the color to monochrome).
    static func nsColor(for fraction: Double) -> NSColor {
        switch UsageLevel.level(for: fraction) {
        case .ok: return .systemGreen
        case .warn: return .systemYellow
        case .critical: return .systemRed
        }
    }
}
