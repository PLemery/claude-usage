# Claude Usage Menu Bar App — Design Spec

**Date:** 2026-06-14
**Status:** Approved (design); pending spec review
**Platform:** macOS only (Darwin 25.5 / macOS 26 confirmed on dev machine)

## 1. Purpose

A native macOS menu-bar utility that shows, at a glance, how close the user is to
their Claude subscription limits, and — on click — a fuller breakdown of usage by
limit window, current chat context size, and per-project token/cost totals.

Inspired by the third-party "AI Battery" app, but built independently. The
screenshot the user shared is inspiration, not a pixel-exact target.

## 2. Success criteria

- A menu-bar item always shows the **current 5-hour usage %**, color-coded.
- Clicking it opens a popover with: 5-Hour, 7-Day, Context, and per-project breakdown.
- The 5-hour and 7-day numbers are **exact** (from Anthropic), including reset countdowns —
  OR, if the usage endpoint is unavailable, gracefully fall back to local estimates.
- Runs menu-bar-only (no Dock icon) and can launch at login.

## 3. Non-goals (YAGNI)

- No Windows/Linux build. Mac-only by explicit decision.
- No historical charts/graphs in v1 (totals and current state only).
- No account management beyond reusing the existing Claude Code login.
- No notifications/alerts in v1 (color change is the only warning). Possible later.

## 4. Architecture

Native Swift app using SwiftUI `MenuBarExtra` (macOS 13+; dev machine is macOS 26).
Menu-bar-only via `LSUIElement` (no Dock icon). Optional launch-at-login via
`SMAppService`.

Two independent data modules feed one view model. Keeping them decoupled means a
failure in one (e.g. the network usage API changing) does not break the other.

```
┌─────────────────────────────────────────────┐
│ MenuBarExtra (SwiftUI)                       │
│  • label: 5-hour % (color-coded)             │
│  • popover: 5-Hour / 7-Day / Context / Proj  │
└───────────────▲──────────────▲───────────────┘
                │              │
        ┌───────┴──────┐ ┌─────┴──────────────┐
        │ LimitsModule │ │ LocalStatsModule   │
        │ (network)    │ │ (filesystem)       │
        └───────▲──────┘ └─────▲──────────────┘
                │              │
   Keychain OAuth token   ~/.claude/projects/**.jsonl
   → usage API            → token / context / cost
```

### 4.1 LimitsModule (network, exact)

- Reads the existing OAuth token from the macOS Keychain entry
  `Claude Code-credentials` (account = current user). No new login required if the
  user is already signed into Claude Code; a fresh "Sign in with Claude" OAuth flow
  is a fallback if the token is missing/expired.
- Calls Anthropic's usage endpoint with that token.
- Returns: 5-hour utilization %, 7-day utilization %, and reset timestamps for each.
- Refresh cadence: every ~60s and on popover open.

**Risk / first step:** the exact usage endpoint is an internal/unofficial API. The
**first implementation task is a ~15-minute spike** to confirm the endpoint responds
with the Keychain token. If it is locked down, fall back to estimating the 5h/7d
gauges from local token counts; all other features are unaffected.

### 4.2 LocalStatsModule (filesystem)

- Parses JSONL transcripts under `~/.claude/projects/<project>/<session>.jsonl`.
- Each assistant message carries a `usage` object:
  `input_tokens`, `output_tokens`, `cache_creation_input_tokens`,
  `cache_read_input_tokens`, plus `model` and a timestamp.
- Computes:
  - **Context %** = token size of the most-recently-active session (newest-modified
    JSONL) as a fraction of the 200K context window.
  - **Per-project totals** = tokens summed per project folder, ranked descending.
  - **Cost estimate** = tokens × public per-model price. Always labeled "~est"; the
    OS does not store real dollar amounts locally.
- Refresh cadence: on popover open (and lightweight enough to re-run on the 60s tick).

## 5. UI

### 5.1 Menu bar item
- Text: current 5-hour usage % (e.g. `3%`).
- Color-coded: green (low) → amber (mid) → red (near limit) so the user gets a
  glanceable warning without opening anything.

### 5.2 Popover (on click)
- **5-Hour:** progress bar, %, "Resets in 4h 37m".
- **7-Day:** progress bar, %, "Resets in 6d 7h".
- **Context:** current session's % of the 200K window.
- **Projects:** ranked by tokens; each row shows total tokens + estimated cost.
- **Footer:** last-refresh time, settings, Quit.

## 6. Key decisions (confirmed with user)

| Decision | Choice |
|----------|--------|
| Platform | macOS only |
| Build | Native Swift / SwiftUI `MenuBarExtra` |
| Limit window | 5-hour (matches Anthropic's real rolling window) |
| Limits source | Exact via Keychain OAuth token → usage API; local-estimate fallback |
| "Context" meaning | Most recently active session |
| Cost | Estimated (tokens × public price), labeled "~est" |
| Refresh | ~60s + on open |
| Visual fidelity | Inspired by AI Battery, not pixel-exact |

## 7. Open questions for spec review

- Launch-at-login on by default, or opt-in via settings? (Proposed: opt-in.)
- Any alert/notification when crossing a threshold (e.g. 80%)? (Proposed: out of
  scope for v1; color is the only warning.)
- App name? (Placeholder: "Claude Usage".)

## 8. First implementation milestone

1. Spike: confirm the usage endpoint answers with the Keychain token.
2. Based on the spike result, lock the LimitsModule to exact-API or estimate mode.
3. Build LocalStatsModule (JSONL parser) in parallel — independent of the spike.
