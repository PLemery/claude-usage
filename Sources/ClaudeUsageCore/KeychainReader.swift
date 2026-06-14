import Foundation
import Security

public enum KeychainReader {
    /// Reads the Claude Code OAuth access token from the login Keychain.
    /// Returns nil if not signed in.
    public static func claudeAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Shape confirmed in Task 2 Step 2; adjust the key path to match the spike.
        let oauth = json["claudeAiOauth"] as? [String: Any]
        return oauth?["accessToken"] as? String
    }

    /// Full Claude Code tokens (access + refresh + expiry) for the optional
    /// "use my existing Claude Code login" import. Returns nil if not signed in.
    public static func claudeCodeTokens() -> OAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String else { return nil }
        // expiresAt is epoch milliseconds.
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            ?? Date().addingTimeInterval(3600)
        return OAuthTokens(accessToken: access,
                           refreshToken: oauth["refreshToken"] as? String,
                           expiresAt: expiresAt)
    }
}
