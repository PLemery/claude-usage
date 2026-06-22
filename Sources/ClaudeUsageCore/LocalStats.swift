import Foundation

/// Rich summary of the most-recently-active Claude Code session (the "current chat").
public struct SessionContext: Equatable {
    public var projectName: String       // from cwd, e.g. "Claude Usage"
    public var sessionId: String         // transcript filename (UUID)
    public var model: String             // friendly, e.g. "Opus 4.8"
    public var turns: Int                // assistant turns in this session
    public var contextTokens: Int        // latest turn's input side (incl cache)
    public var windowTokens: Int         // model/size-aware context window
    public var startedAt: Date
    public var lastActivity: Date
    public var freshInputTokens: Int     // input + cacheCreation across turns (excludes cache reads)
    public var outputTokens: Int         // output across turns

    public init(projectName: String, sessionId: String, model: String, turns: Int,
                contextTokens: Int, windowTokens: Int, startedAt: Date, lastActivity: Date,
                freshInputTokens: Int, outputTokens: Int) {
        self.projectName = projectName; self.sessionId = sessionId; self.model = model
        self.turns = turns; self.contextTokens = contextTokens; self.windowTokens = windowTokens
        self.startedAt = startedAt; self.lastActivity = lastActivity
        self.freshInputTokens = freshInputTokens; self.outputTokens = outputTokens
    }

    public var shortId: String { String(sessionId.prefix(8)) }
    public var fraction: Double { windowTokens > 0 ? Double(contextTokens) / Double(windowTokens) : 0 }
    public var duration: TimeInterval { max(lastActivity.timeIntervalSince(startedAt), 0) }
    /// Fresh (non-cache) tokens processed per minute over the session.
    public var tokensPerMinute: Double {
        let mins = duration / 60
        return mins > 0 ? Double(freshInputTokens + outputTokens) / mins : 0
    }
    public var inputOutputRatio: Double {
        outputTokens > 0 ? Double(freshInputTokens) / Double(outputTokens) : 0
    }
    public var isLongConversation: Bool { turns >= 100 }
    public var isHighIORatio: Bool { inputOutputRatio >= 20 }
}

public struct LocalStatsResult: Equatable {
    public var projects: [ProjectUsage]       // ranked by total tokens, descending
    public var currentContextTokens: Int      // input side of newest turn across all sessions
    public var currentSession: SessionContext?
}

public enum LocalStats {
    /// Default location of Claude Code transcripts.
    public static func defaultProjectsRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    public static func scan(projectsRoot: URL) throws -> LocalStatsResult {
        let fm = FileManager.default
        var projects: [ProjectUsage] = []
        var newestTs: Date = .distantPast
        var current: SessionContext?

        let folders = (try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            var folderUsage = TokenUsage()
            var folderTurns: [TranscriptTurn] = []
            let projectName = lastCwd(in: folder).map { ($0 as NSString).lastPathComponent } ?? folder.lastPathComponent

            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let turns = (try? JSONLParser.parse(fileAt: file)) ?? []
                folderTurns += turns
                for t in turns { folderUsage = folderUsage + t.usage }
                if let maxTs = turns.map(\.timestamp).max(), maxTs > newestTs {
                    newestTs = maxTs
                    current = buildSession(turns: turns,
                                           sessionId: file.deletingPathExtension().lastPathComponent,
                                           projectName: projectName)
                }
            }
            if folderUsage.total == 0 { continue }
            projects.append(ProjectUsage(name: projectName, usage: folderUsage,
                                         estimatedCostUSD: CostEstimator.costUSD(of: folderTurns)))
        }

        projects.sort { $0.usage.fresh > $1.usage.fresh }
        return LocalStatsResult(projects: projects,
                                currentContextTokens: current?.contextTokens ?? 0,
                                currentSession: current)
    }

    private static func buildSession(turns: [TranscriptTurn], sessionId: String, projectName: String) -> SessionContext? {
        let sorted = turns.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let contextTokens = last.usage.input + last.usage.cacheCreation + last.usage.cacheRead
        let freshInput = turns.reduce(0) { $0 + $1.usage.input + $1.usage.cacheCreation }
        let output = turns.reduce(0) { $0 + $1.usage.output }
        // Most recent real (non-synthetic) model the session used.
        let modelRaw = sorted.reversed().first { !$0.model.lowercased().contains("synthetic") }?.model ?? last.model
        let window = contextWindow(forModel: modelRaw)
        return SessionContext(projectName: projectName, sessionId: sessionId,
                              model: friendlyModel(modelRaw), turns: turns.count,
                              contextTokens: contextTokens, windowTokens: window,
                              startedAt: first.timestamp, lastActivity: last.timestamp,
                              freshInputTokens: freshInput, outputTokens: output)
    }

    /// Real context-window size per model family. Opus/Sonnet/Fable/Mythos are 1M;
    /// Haiku is 200K; unknown models default to a conservative 200K.
    static func contextWindow(forModel model: String) -> Int {
        let s = model.lowercased()
        if s.contains("haiku") { return 200_000 }
        if s.contains("opus") || s.contains("sonnet") || s.contains("fable") || s.contains("mythos") { return 1_000_000 }
        return 200_000
    }

    /// "claude-opus-4-8" → "Opus 4.8"; "sonnet" → "Sonnet"; unknown → passthrough.
    static func friendlyModel(_ m: String) -> String {
        let s = m.lowercased()
        let family = s.contains("opus") ? "Opus" : s.contains("haiku") ? "Haiku" : s.contains("sonnet") ? "Sonnet" : nil
        guard let family else { return m }
        if let r = s.range(of: #"\d+-\d+"#, options: .regularExpression) {
            return "\(family) \(s[r].replacingOccurrences(of: "-", with: "."))"
        }
        return family
    }

    /// Reads the `cwd` of the last assistant line in a folder, for a friendly project name.
    private static func lastCwd(in folder: URL) -> String? {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        guard let newestFile = files.filter({ $0.pathExtension == "jsonl" })
            .max(by: { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return da < db
            }),
            let text = try? String(contentsOf: newestFile, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cwd = obj["cwd"] as? String { return cwd }
        }
        return nil
    }
}
