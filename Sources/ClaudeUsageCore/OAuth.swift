import Foundation
import CryptoKit
import Security

/// Lightweight diagnostic log at ~/Library/Logs/ClaudeUsage.log
public enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClaudeUsage.log")
    public static func write(_ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Tokens we obtain from the "Sign in with Claude" flow and store ourselves.
public struct OAuthTokens: Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }
    /// True if expired (with a 60s safety margin).
    public var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

public enum OAuthError: Error, LocalizedError {
    case server(Int, String)
    case decode
    public var errorDescription: String? {
        switch self {
        case .server(let code, let msg): return "Sign-in failed (\(code)): \(msg)"
        case .decode: return "Could not read the sign-in response."
        }
    }
}

/// The public Claude Code OAuth client + endpoints (same flow Claude Code uses).
public enum OAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    // Consumer-subscription OAuth context (claude.ai + console.anthropic.com). The
    // platform.claude.com endpoints are the developer/console context, where a personal
    // org's "OAuth not allowed" policy 403s the usage endpoint. These are the well-known
    // Claude Code / OpenCode constants.
    public static let authorizeBase = "https://claude.ai/oauth/authorize"
    public static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    /// Redirect that shows the user a copyable `code#state`.
    public static let manualRedirect = "https://console.anthropic.com/oauth/code/callback"
    public static let scopes = "org:create_api_key user:profile user:inference"

    // MARK: PKCE

    public static func makeVerifier() -> String {
        base64url(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
    }
    public static func challenge(for verifier: String) -> String {
        base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    static func base64url(_ d: Data) -> String {
        d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: URLs

    public static func authorize(redirect: String, challenge: String, state: String) -> URL {
        var c = URLComponents(string: authorizeBase)!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return c.url!
    }

    // MARK: Token exchange / refresh

    public static func exchange(code: String, verifier: String, state: String, redirect: String) async throws -> OAuthTokens {
        try await post([
            "grant_type": "authorization_code",
            "code": code, "state": state,
            "client_id": clientID, "redirect_uri": redirect,
            "code_verifier": verifier,
        ])
    }

    public static func refresh(_ refreshToken: String) async throws -> OAuthTokens {
        try await post([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    private static func post(_ body: [String: Any]) async throws -> OAuthTokens {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        let grant = (body["grant_type"] as? String) ?? "?"
        guard code == 200 else {
            Log.write("oauth token endpoint [\(grant)] HTTP \(code): \(String(data: data, encoding: .utf8)?.prefix(200) ?? "")")
            throw OAuthError.server(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else {
            Log.write("oauth token endpoint [\(grant)] 200 but could not parse access_token")
            throw OAuthError.decode
        }
        Log.write("oauth token endpoint [\(grant)] OK — granted scope: \(obj["scope"] as? String ?? "?")")
        let expiresIn = (obj["expires_in"] as? Double) ?? 3600
        return OAuthTokens(accessToken: access,
                           refreshToken: obj["refresh_token"] as? String,
                           expiresAt: Date().addingTimeInterval(expiresIn))
    }
}

/// Stores our own tokens in a dedicated Keychain entry (not Claude Code's).
public enum TokenStore {
    static let service = "ClaudeUsage-credentials"

    public static func save(_ t: OAuthTokens) {
        guard let data = try? JSONEncoder().encode(t) else { return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    public static func load() -> OAuthTokens? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: d)
    }

    public static func clear() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service] as CFDictionary)
    }
}
