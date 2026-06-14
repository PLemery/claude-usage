# Claude Usage

A macOS menu-bar app showing your live Claude usage: 5-hour limit %, 7-day limit %,
current chat context size, and per-project token/cost estimates.

## Build
    ./scripts/make-app.sh
    open ClaudeUsage.app

## Move to Applications (optional)
    cp -R ClaudeUsage.app /Applications/

## Notes
- Reuses your existing Claude Code login (macOS Keychain). No separate sign-in.
- Limit %s come from Anthropic's usage endpoint (exact). If unavailable, the app
  falls back to local estimates.
- Costs are ESTIMATES (tokens × public list price), not billed amounts.
