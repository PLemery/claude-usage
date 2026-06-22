import Foundation
import AppKit
import Network
import ClaudeUsageCore

/// Runs a closure exactly once (state updates arrive serially on one queue).
private final class Once { private var done = false; func run(_ b: () -> Void) { if !done { done = true; b() } } }

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn: Bool = TokenStore.load() != nil
    @Published var awaitingPaste = false        // show the paste field
    @Published var inProgress = false           // a sign-in is underway
    @Published var status: String?

    /// Called after sign-in/out so the app can refresh data.
    var onAuthChange: (() -> Void)?

    private var verifier = ""
    private var state = ""
    private var redirect = ""
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "claudeusage.oauth.loopback")

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

    // MARK: Sign-in

    func signIn() {
        verifier = OAuth.makeVerifier()
        state = UUID().uuidString
        awaitingPaste = false
        inProgress = true
        status = "Opening your browser…"
        Task { await beginAutoOrManual() }
    }

    private func beginAutoOrManual() async {
        let challenge = OAuth.challenge(for: verifier)
        if let port = await startLoopback() {
            redirect = "http://localhost:\(port)/callback"
            status = "Waiting for sign-in in your browser…"
        } else {
            redirect = OAuth.manualRedirect
            awaitingPaste = true
            status = "Approve in your browser, then paste the code below."
        }
        NSWorkspace.shared.open(OAuth.authorize(redirect: redirect, challenge: challenge, state: state))
    }

    /// User clicked "Paste a code instead" — reopen with the manual redirect.
    func switchToPaste() {
        listener?.cancel(); listener = nil
        redirect = OAuth.manualRedirect
        awaitingPaste = true
        status = "Approve in your browser, then paste the code below."
        NSWorkspace.shared.open(OAuth.authorize(redirect: redirect,
                                                challenge: OAuth.challenge(for: verifier), state: state))
    }

    func submitPaste(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The platform callback shows "code#state".
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? trimmed
        let st = parts.count > 1 ? parts[1] : state
        Task { await finish(code: code, state: st, redirect: OAuth.manualRedirect) }
    }

    /// Optional shortcut: import the existing Claude Code login from the Keychain.
    func useClaudeCodeLogin() {
        if let tokens = KeychainReader.claudeCodeTokens() {
            TokenStore.save(tokens)
            isSignedIn = true; inProgress = false; status = nil
            Log.write("import: Claude Code login imported, token stored")
            onAuthChange?()
        } else {
            status = "No Claude Code login found on this Mac."
            Log.write("import: no Claude Code login found / keychain read blocked")
        }
    }

    func signOut() {
        listener?.cancel(); listener = nil
        TokenStore.clear()
        isSignedIn = false; inProgress = false; awaitingPaste = false; status = nil
        onAuthChange?()
    }

    func cancel() {
        listener?.cancel(); listener = nil
        inProgress = false; awaitingPaste = false; status = nil
    }

    private func finish(code: String, state: String, redirect: String) async {
        status = "Signing in…"
        Log.write("sign-in: exchanging code (len=\(code.count)) via redirect=\(redirect)")
        do {
            let tokens = try await OAuth.exchange(code: code, verifier: verifier, state: state, redirect: redirect)
            TokenStore.save(tokens)
            listener?.cancel(); listener = nil
            isSignedIn = true; inProgress = false; awaitingPaste = false; status = nil
            Log.write("sign-in: SUCCESS, token stored")
            onAuthChange?()
        } catch {
            status = (error as? OAuthError)?.errorDescription ?? error.localizedDescription
            Log.write("sign-in: FAILED — \(error)")
        }
    }

    // MARK: Loopback callback server

    /// Starts a localhost listener; returns the bound port, or nil if it couldn't start.
    private func startLoopback() async -> UInt16? {
        await withCheckedContinuation { (cont: CheckedContinuation<UInt16?, Never>) in
            let once = Once()
            do {
                let l = try NWListener(using: .tcp)
                listener = l
                l.stateUpdateHandler = { st in
                    switch st {
                    case .ready: once.run { cont.resume(returning: l.port?.rawValue) }
                    case .failed, .cancelled: once.run { cont.resume(returning: nil) }
                    default: break
                    }
                }
                l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                l.start(queue: queue)
            } catch {
                once.run { cont.resume(returning: nil) }
            }
        }
    }

    private nonisolated func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            var code: String?
            var st: String?
            if let data, let req = String(data: data, encoding: .utf8),
               let requestLine = req.split(separator: "\r\n").first {
                // "GET /callback?code=...&state=... HTTP/1.1"
                let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let comps = URLComponents(string: "http://localhost\(path)")
                code = comps?.queryItems?.first { $0.name == "code" }?.value
                st = comps?.queryItems?.first { $0.name == "state" }?.value
            }
            let html = "<html><body style='font-family:-apple-system;text-align:center;padding:60px'>"
                + "<h2>✓ Signed in to ClaudeUsage</h2><p>You can close this tab.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            conn.send(content: response.data(using: .utf8),
                      completion: .contentProcessed { _ in conn.cancel() })
            if let code {
                Task { @MainActor in await self.finish(code: code, state: st ?? self.state, redirect: self.redirect) }
            }
        }
    }
}
