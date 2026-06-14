import SwiftUI
import ClaudeUsageCore

struct UsagePopover: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage").font(.headline)

            window("5-Hour", vm.snapshot?.fiveHour)
            window("7-Day", vm.snapshot?.sevenDay)

            if let w = vm.snapshot?.wallet, w.isEnabled {
                Divider()
                row(title: "Extra usage",
                    trailing: "$\(String(format: "%.2f", w.used)) / $\(String(format: "%.2f", w.limit))")
                ProgressView(value: min(w.utilization, 1))
                Text("$\(String(format: "%.2f", w.remaining)) left this month")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let ctx = vm.stats?.currentContextTokens {
                Divider()
                let frac = Double(ctx) / Double(ClaudeUsageCore.contextWindowTokens)
                row(title: "Context", trailing: "\(Int((frac*100).rounded()))%")
                ProgressView(value: min(frac, 1))
            }

            if let projects = vm.stats?.projects, !projects.isEmpty {
                Divider()
                Text("Projects (~est cost)").font(.subheadline).bold()
                ForEach(projects.prefix(5), id: \.name) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text("~$\(p.estimatedCostUSD, specifier: "%.0f")").foregroundStyle(.secondary)
                        Text(format(p.usage.total)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    }.font(.callout)
                }
            }

            Divider()
            HStack {
                if let t = vm.lastUpdated {
                    Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await vm.refresh() } }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private func window(_ title: String, _ w: LimitWindow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).bold()
                Spacer()
                Text(w.map { "\(Int(($0.fraction*100).rounded()))%" } ?? "—")
            }
            ProgressView(value: min(w?.fraction ?? 0, 1))
            if let w { Text("Resets \(w.resetsAt.formatted(.relative(presentation: .named)))")
                .font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func row(title: String, trailing: String) -> some View {
        HStack { Text(title).bold(); Spacer(); Text(trailing) }
    }

    private func format(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n)/1_000_000) }
        if n >= 1_000 { return "\(n/1000)K" }
        return "\(n)"
    }
}
