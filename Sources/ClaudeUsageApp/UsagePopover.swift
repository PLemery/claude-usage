import SwiftUI
import ClaudeUsageCore

struct UsagePopover: View {
    @ObservedObject var vm: AppViewModel
    @ObservedObject var auth: AuthManager
    @State private var pasteText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage").font(.headline)

            if auth.isSignedIn {
                window("5-Hour", vm.snapshot?.fiveHour)
                window("7-Day", vm.snapshot?.sevenDay)

                if let w = vm.snapshot?.wallet, w.isEnabled {
                    Divider()
                    row(title: "Extra usage",
                        trailing: "$\(String(format: "%.2f", w.used)) / $\(String(format: "%.2f", w.limit))")
                    ProgressView(value: min(w.utilization, 1))
                        .tint(AppViewModel.color(for: w.utilization))
                    Text("$\(String(format: "%.2f", w.remaining)) left this month")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                signInCard
            }

            if let s = vm.stats?.currentSession {
                Divider()
                contextSection(s)
            }

            if let projects = vm.stats?.projects, !projects.isEmpty {
                Divider()
                Text("Projects (~est cost)").font(.subheadline).bold()
                ForEach(projects.prefix(5), id: \.name) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text("~$\(p.estimatedCostUSD, specifier: "%.0f")").foregroundStyle(.secondary)
                        Text(format(p.usage.fresh)).monospacedDigit().frame(width: 56, alignment: .trailing)
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
                if auth.isSignedIn { Button("Sign out") { auth.signOut() } }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: - Sign-in

    @ViewBuilder private var signInCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to see your limits").font(.subheadline).bold()
            Text("Connects to your Claude account to read your usage. Works for any Claude plan.")
                .font(.caption).foregroundStyle(.secondary)

            if auth.inProgress {
                if auth.awaitingPaste {
                    TextField("Paste the code from your browser", text: $pasteText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Submit") { auth.submitPaste(pasteText); pasteText = "" }
                            .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { auth.cancel() }
                    }
                } else {
                    HStack {
                        Button("Paste a code instead") { auth.switchToPaste() }
                        Spacer()
                        Button("Cancel") { auth.cancel() }
                    }.font(.caption)
                }
            } else {
                Button("Sign in with Claude") { auth.signIn() }
                    .buttonStyle(.borderedProminent)
                Button("Use my Claude Code login") { auth.useClaudeCodeLogin() }
                    .font(.caption).buttonStyle(.link)
            }

            if let s = auth.status {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Context

    @ViewBuilder private func contextSection(_ s: SessionContext) -> some View {
        HStack {
            Text("Context").bold()
            Spacer()
            Circle().fill(AppViewModel.color(for: s.fraction)).frame(width: 9, height: 9)
            Text(pct(s.fraction)).bold().monospacedDigit()
        }
        Text("\(s.projectName) · \(s.shortId)")
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        Text("\(durationStr(s.duration)) · \(s.lastActivity.formatted(.relative(presentation: .named))) · \(rateStr(s.tokensPerMinute))")
            .font(.caption).foregroundStyle(.secondary)
        ProgressView(value: min(s.fraction, 1))
            .tint(AppViewModel.color(for: s.fraction))
        HStack {
            Text("~\(format(s.contextTokens)) of \(format(s.windowTokens)) usable")
            Spacer()
            Text("\(s.turns) turns · \(s.model)")
        }
        .font(.caption).foregroundStyle(.secondary)
        if s.isLongConversation {
            Label("Long conversation (\(s.turns) turns)", systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
        if s.isHighIORatio {
            Label("High input-to-output ratio (\(Int(s.inputOutputRatio)):1)", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func window(_ title: String, _ w: LimitWindow?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).bold()
                Spacer()
                Text(w.map { pct($0.fraction) } ?? "—").monospacedDigit()
            }
            ProgressView(value: min(w?.fraction ?? 0, 1))
                .tint(AppViewModel.color(for: w?.fraction ?? 0))
            if let w {
                Text("Resets \(w.resetsAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(title: String, trailing: String) -> some View {
        HStack { Text(title).bold(); Spacer(); Text(trailing).monospacedDigit() }
    }

    // MARK: - Formatting

    private func pct(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }

    private func format(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)K" }
        return "\(n)"
    }

    private func durationStr(_ t: TimeInterval) -> String {
        let mins = Int(t / 60)
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }

    private func rateStr(_ perMin: Double) -> String {
        if perMin >= 1000 { return String(format: "%.1fK/min", perMin / 1000) }
        return "\(Int(perMin))/min"
    }
}
