import XCTest
@testable import ClaudeUsageCore

final class OAuthTests: XCTestCase {
    /// RFC 7636 Appendix B test vector — proves our PKCE S256 challenge is correct.
    func testPKCEChallengeMatchesRFC7636() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(OAuth.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierIsURLSafe() {
        let v = OAuth.makeVerifier()
        XCTAssertFalse(v.contains("+") || v.contains("/") || v.contains("="))
        XCTAssertFalse(v.isEmpty)
    }

    func testAuthorizeURLHasPKCEParams() {
        let url = OAuth.authorize(redirect: "http://localhost:1234/callback",
                                  challenge: "abc", state: "xyz")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["client_id"], OAuth.clientID)
        XCTAssertEqual(dict["code_challenge_method"], "S256")
        XCTAssertEqual(dict["code_challenge"], "abc")
        XCTAssertEqual(dict["redirect_uri"], "http://localhost:1234/callback")
    }
}
