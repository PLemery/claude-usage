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
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]

        let folders = (try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            var folderUsage = TokenUsage()
            var folderTurns: [TranscriptTurn] = []

            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
                .filter { $0.pathExtension == "jsonl" }
            var parsed: [(url: URL, mtime: Date, entry: FileCache.Entry)] = []
            for file in files {
                let rv = try? file.resourceValues(forKeys: Set(keys))
                let mtime = rv?.contentModificationDate ?? .distantPast
                guard let entry = FileCache.shared.entry(for: file, size: rv?.fileSize ?? 0, mtime: mtime) else { continue }
                parsed.append((file, mtime, entry))
            }
            // Friendly name = cwd of the most recently modified transcript in the folder.
            let projectName = parsed.max(by: { $0.mtime < $1.mtime })?.entry.lastCwd
                .map { ($0 as NSString).lastPathComponent } ?? folder.lastPathComponent

            for (file, _, entry) in parsed {
                let turns = entry.turns
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
}

/// Per-file parse cache. Transcripts are append-only, so when a file grows we only
/// parse the new bytes; unchanged files cost a single stat() per scan.
final class FileCache {
    static let shared = FileCache()

    struct Entry {
        var size: Int
        var mtime: Date
        var offset: UInt64              // bytes consumed through the last complete line
        var committed: JSONLParser.Chunk  // parsed from complete (newline-terminated) lines
        var tail: JSONLParser.Chunk       // parsed from a trailing partial line, re-done on growth

        var turns: [TranscriptTurn] { committed.turns + tail.turns }
        var lastCwd: String? { tail.lastCwd ?? committed.lastCwd }
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    func entry(for url: URL, size: Int, mtime: Date) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        let key = url.path
        var e = entries[key]
        if let cached = e, cached.size == size, cached.mtime == mtime { return cached }
        if let cached = e, size < cached.size { e = nil }   // truncated/rewritten: start over
        var entry = e ?? Entry(size: 0, mtime: mtime, offset: 0, committed: .init(), tail: .init())

        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard (try? fh.seek(toOffset: entry.offset)) != nil,
              let new = try? fh.readToEnd() else { return nil }

        let nl = UInt8(ascii: "\n")
        let complete = new.lastIndex(of: nl).map { new[new.startIndex...$0] } ?? Data()
        let rest = new[(complete.endIndex)...]
        let parsed = JSONLParser.parse(data: complete)
        entry.committed.turns += parsed.turns
        if let c = parsed.lastCwd { entry.committed.lastCwd = c }
        entry.offset += UInt64(complete.count)
        entry.tail = JSONLParser.parse(data: rest)
        entry.size = size
        entry.mtime = mtime
        entries[key] = entry
        return entry
    }
}
