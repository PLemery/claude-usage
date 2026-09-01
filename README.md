# Claude Usage

A macOS menu-bar app showing your live Claude usage: 5-hour limit %, 7-day limit %,
current chat context size, and per-project token/cost estimates.

## Download

Grab the latest `.zip` from [Releases](https://github.com/PLemery/claude-usage/releases),
unzip it, and move `ClaudeUsage.app` to Applications.

The app is ad-hoc signed, not notarized (no Apple Developer account), so macOS
Gatekeeper will block it as "Apple could not verify this app is free of malware."
To open it anyway, run this once in Terminal:

    xattr -cr /Applications/ClaudeUsage.app

Then open it normally. This removes the quarantine flag macOS adds to anything
downloaded from a browser — it's the standard fix for unsigned/ad-hoc-signed
apps and only needs to be done once per copy of the app.

## Build from source
    ./scripts/make-app.sh
    open ClaudeUsage.app

## Move to Applications (optional)
    cp -R ClaudeUsage.app /Applications/

## Notes
- Reuses your existing Claude Code login (macOS Keychain). No separate sign-in.
- Limit %s come from Anthropic's usage endpoint (exact). If unavailable, the app
  falls back to local estimates.
- Costs are ESTIMATES (tokens × public list price), not billed amounts.
