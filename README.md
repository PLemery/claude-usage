# Claude Usage

A macOS menu-bar app showing your live Claude usage: 5-hour limit %, 7-day limit %,
current chat context size, and per-project token/cost estimates.

## Download

Grab the latest `.zip` from [Releases](https://github.com/PLemery/claude-usage/releases),
unzip it, and move `ClaudeUsage.app` to Applications.

Releases starting from the Developer ID era are signed and notarized by
Apple — just unzip, move to Applications, and open normally, no warnings.

If you somehow ended up with an older, un-notarized copy (ad-hoc signed only),
macOS Gatekeeper will block it as "Apple could not verify this app is free of
malware." Fix it once with:

    xattr -cr /Applications/ClaudeUsage.app

This removes the quarantine flag macOS adds to anything downloaded from a
browser.

## Development

Two build modes, kept deliberately separate so a local code change never
reaches anyone else's copy of the app until you explicitly decide to ship it.

### Just testing something locally

    ./scripts/make-app.sh --install
    open /Applications/ClaudeUsage.app

Fast (~3s), ad-hoc signed, no network calls, never distributed. The version
shown in the app gets a `-dev` suffix (e.g. `1.2-dev`) so a dev build is
always visually distinguishable from a real release. Run this as often as
you want — quit the running app first if it's already open.

### Cutting an actual release

    ./scripts/make-app.sh --release   # signs with the real Developer ID cert, no "-dev" suffix
    ./scripts/notarize.sh             # submits to Apple, staples the ticket, builds ClaudeUsage.zip

`--release` requires the "Developer ID Application: Parker Lemery" certificate
to be present in Keychain Access, and `notarize.sh` requires notarization
credentials already stored under the `notarytool-profile` keychain profile
(`xcrun notarytool store-credentials`).

Producing the notarized zip does **not** by itself push the update to anyone
— existing installs only learn about a new version when the `appcast.xml`
feed (checked via Sparkle, see `SUFeedURL` in `make-app.sh`) is updated to
point at it. That feed update is a separate, deliberate step: build the
release, bump the version numbers in `make-app.sh`, sign the zip with
Sparkle's `sign_update` tool, add an entry to `appcast.xml`, then push and
create the GitHub Release with the zip attached. Nothing rolls out until
that push happens.

## Notes
- Reuses your existing Claude Code login (macOS Keychain). No separate sign-in.
- Limit %s come from Anthropic's usage endpoint (exact). If unavailable, the app
  falls back to local estimates.
- Costs are ESTIMATES (tokens × public list price), not billed amounts.
