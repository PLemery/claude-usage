import Foundation

public enum JSONLParser {
    private struct Line: Decodable {
        let type: String?
        let timestamp: Date?
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

    /// Returns assistant turns (in file order) that carry a usage object.
    public static func parse(fileAt url: URL) throws -> [TranscriptTurn] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        var turns: [TranscriptTurn] = []
        for raw in data.split(separator: UInt8(ascii: "\n")) where !raw.isEmpty {
            guard let line = try? decoder.decode(Line.self, from: Data(raw)),
                  line.type == "assistant",
                  let msg = line.message, let usage = msg.usage else { continue }
            turns.append(TranscriptTurn(
                model: msg.model ?? "unknown",
                usage: TokenUsage(
                    input: usage.input_tokens ?? 0,
                    output: usage.output_tokens ?? 0,
                    cacheCreation: usage.cache_creation_input_tokens ?? 0,
                    cacheRead: usage.cache_read_input_tokens ?? 0),
                timestamp: line.timestamp ?? .distantPast))
        }
        return turns
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// ISO-8601 with fractional seconds (e.g. 2026-04-11T17:32:33.357Z).
    static let iso8601WithFractionalSeconds = custom { decoder in
        let s = try decoder.singleValueContainer().decode(String.self)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad date: \(s)"))
    }
}
