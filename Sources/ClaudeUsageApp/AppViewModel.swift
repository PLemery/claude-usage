import Foundation
import SwiftUI
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
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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

    var menuBarColor: Color {
        switch UsageLevel.level(for: snapshot?.fiveHour?.fraction ?? 0) {
        case .ok: return .green
        case .warn: return .orange
        case .critical: return .red
        }
    }
}
