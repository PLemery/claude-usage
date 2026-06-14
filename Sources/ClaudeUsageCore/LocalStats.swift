import Foundation

public struct LocalStatsResult: Equatable {
    public var projects: [ProjectUsage]      // ranked by total tokens, descending
    public var currentContextTokens: Int     // input side of newest turn across all sessions
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
        var newest: TranscriptTurn?

        let folders = (try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            var folderUsage = TokenUsage()
            var folderTurns: [TranscriptTurn] = []
            var projectName = folder.lastPathComponent

            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let turns = (try? JSONLParser.parse(fileAt: file)) ?? []
                folderTurns += turns
                for t in turns {
                    folderUsage = folderUsage + t.usage
                    if let n = newest { if t.timestamp > n.timestamp { newest = t } } else { newest = t }
                }
            }
            if folderUsage.total == 0 { continue }
            // Prefer the human project name from cwd if available.
            if let cwd = lastCwd(in: folder) { projectName = (cwd as NSString).lastPathComponent }
            projects.append(ProjectUsage(name: projectName, usage: folderUsage,
                                         estimatedCostUSD: CostEstimator.costUSD(of: folderTurns)))
        }

        projects.sort { $0.usage.total > $1.usage.total }
        let contextTokens = newest.map { $0.usage.input + $0.usage.cacheCreation + $0.usage.cacheRead } ?? 0
        return LocalStatsResult(projects: projects, currentContextTokens: contextTokens)
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
