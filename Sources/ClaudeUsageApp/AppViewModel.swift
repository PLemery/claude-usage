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

    private var timer: Timer?

    func start() {
        Task { await refresh() }
        LoginItem.promptForLaunchAtLoginIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        do { snapshot = try await UsageAPIClient.fetch(); errorText = nil }
        catch { errorText = "Limits unavailable" }
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
