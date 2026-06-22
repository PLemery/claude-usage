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
    private var cooldownUntil: Date?   // back off after a 429

    func start() {
        auth.onAuthChange = { [weak self] in Task { await self?.refresh() } }
        Task { await refresh() }
        LoginItem.promptForLaunchAtLoginIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        if let token = await auth.validAccessToken() {
            if let until = cooldownUntil, Date() < until {
                // Rate-limited recently: keep the last snapshot, skip the network call.
            } else {
                do {
                    snapshot = try await UsageAPIClient.fetch(accessToken: token)
                    errorText = nil; cooldownUntil = nil
                } catch UsageAPIError.rateLimited {
                    errorText = "Rate limited — retrying shortly"
                    cooldownUntil = Date().addingTimeInterval(120)   // back off 2 min, keep last data
                } catch {
                    errorText = "Limits unavailable"
                }
            }
        } else {
            snapshot = nil          // signed out — the popover shows a sign-in prompt
            errorText = nil
        }
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
