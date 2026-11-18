import Foundation

public enum JSONLParser {
    private struct Line: Decodable {
        let type: String?
        let timestamp: Date?
        let cwd: String?
        let message: Message?
        struct Message: Decodable {
            let model: String?
            let usage: Usage?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    /// Result of parsing a chunk of JSONL: assistant turns plus the last `cwd` seen.
    public struct Chunk {
        public var turns: [TranscriptTurn] = []
        public var lastCwd: String?
    }

    /// Returns assistant turns (in file order) that carry a usage object.
    public static func parse(fileAt url: URL) throws -> [TranscriptTurn] {
        parse(data: try Data(contentsOf: url)).turns
    }

    /// Parses newline-delimited JSON. Lines that fail to decode are skipped.
    public static func parse<D: DataProtocol>(data: D) -> Chunk where D.SubSequence: DataProtocol {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        var chunk = Chunk()
        for raw in data.split(separator: UInt8(ascii: "\n")) where !raw.isEmpty {
            // ~93% of transcript bytes are user/tool-result lines we never use. A raw
            // byte search is far cheaper than a full JSON decode, so skip anything that
            // can't be an assistant turn. (False positives just fall through to decode.)
            let bytes = Data(raw)
            guard bytes.range(of: assistantMarker) != nil,
                  let line = try? decoder.decode(Line.self, from: bytes) else { continue }
            if let cwd = line.cwd { chunk.lastCwd = cwd }
            guard line.type == "assistant", let msg = line.message, let usage = msg.usage else { continue }
            chunk.turns.append(TranscriptTurn(
                model: msg.model ?? "unknown",
                usage: TokenUsage(
                    input: usage.input_tokens ?? 0,
                    output: usage.output_tokens ?? 0,
                    cacheCreation: usage.cache_creation_input_tokens ?? 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0),
                timestamp: line.timestamp ?? .distantPast))
        }
        return chunk
    }
}

private let assistantMarker = Data(#""assistant""#.utf8)

/// ISO8601DateFormatter is expensive to create (ICU setup) but thread-safe to share,
/// so build the two variants once instead of once per decoded line.
private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

extension JSONDecoder.DateDecodingStrategy {
    /// ISO-8601 with fractional seconds (e.g. 2026-04-11T17:32:33.357Z).
    static let iso8601WithFractionalSeconds = custom { decoder in
        let s = try decoder.singleValueContainer().decode(String.self)
        if let d = isoFractional.date(from: s) ?? isoPlain.date(from: s) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date: \(s)"))
    }
}
