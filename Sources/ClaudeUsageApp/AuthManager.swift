import Foundation
import AppKit
import ClaudeUsageCore

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn: Bool = TokenStore.load() != nil
    @Published var awaitingPaste = false     // showing the paste field
    @Published var inProgress = false        // a sign-in is underway
    @Published var status: String?

    /// Called after sign-in/out so the app can refresh data.
    var onAuthChange: (() -> Void)?

    private var verifier = ""
    private var state = ""

    /// A valid access token, refreshing if expired. nil if not signed in / refresh failed.
    func validAccessToken() async -> String? {
        guard var tokens = TokenStore.load() else { return nil }
        if tokens.isExpired {
            guard let rt = tokens.refreshToken,
                  let refreshed = try? await OAuth.refresh(rt) else { return nil }
            tokens = refreshed
            TokenStore.save(tokens)
        }
        return tokens.accessToken
    }

    /// Opens the browser to claude.ai; the page shows a `code#state` to paste back.
    func signIn() {
        verifier = OAuth.makeVerifier()
        state = UUID().uuidString
        inProgress = true
        awaitingPaste = true
        status = "Approve in your browser, then paste the code below."
        let url = OAuth.authorize(redirect: OAuth.manualRedirect,
                                  challenge: OAuth.challenge(for: verifier), state: state)
        NSWorkspace.shared.open(url)
        Log.write("sign-in: opened \(OAuth.authorizeBase) (paste flow)")
    }

    func submitPaste(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The callback page shows "code#state".
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? trimmed
        let st = parts.count > 1 ? parts[1] : state
        Task { await finish(code: code, state: st) }
    }

    /// Optional shortcut: import the existing Claude Code login from the Keychain.
    func useClaudeCodeLogin() {
        if let tokens = KeychainReader.claudeCodeTokens() {
            TokenStore.save(tokens)
            isSignedIn = true; inProgress = false; awaitingPaste = false; status = nil
            Log.write("import: Claude Code login imported, token stored")
            onAuthChange?()
        } else {
            status = "No Claude Code login found on this Mac."
            Log.write("import: no Claude Code login found / keychain read blocked")
        }
    }

    func signOut() {
        TokenStore.clear()
        isSignedIn = false; inProgress = false; awaitingPaste = false; status = nil
        onAuthChange?()
    }

    func cancel() {
        inProgress = false; awaitingPaste = false; status = nil
    }

    private func finish(code: String, state: String) async {
        status = "Signing in…"
        Log.write("sign-in: exchanging code (len=\(code.count))")
        do {
            let tokens = try await OAuth.exchange(code: code, verifier: verifier,
                                                  state: state, redirect: OAuth.manualRedirect)
            TokenStore.save(tokens)
            isSignedIn = true; inProgress = false; awaitingPaste = false; status = nil
            Log.write("sign-in: SUCCESS, token stored")
            onAuthChange?()
        } catch {
            status = (error as? OAuthError)?.errorDescription ?? error.localizedDescription
            Log.write("sign-in: FAILED — \(error)")
        }
    }
}
