# Reset-Time Display Consistency

**Date:** 2026-04-16
**Area:** `Sources/ClaudeBarUI/Views/UsageDetailView.swift`, `Sources/ClaudeBarUI/Resources/*/Localizable.strings`

## Problem

The popover shows two different reset-time formats side by side:

- **5-hour window** (`fiveHourSection`): `Resets in 2h 30m` — relative duration, produced by `resetTimeString()`.
- **7-day windows** (`slimBar` — Total / Opus / Sonnet): `· resets Thu` — abbreviated weekday only, produced by `shortResetString()` through a `DateFormatter` with format `"EEE"`.

The 7-day variant is hard to interpret: it drops the time-of-day entirely and, for a Russian user, collapses to `· сброс Чт`. There is no indication of how many days remain or at what hour the window rolls over. The two sections look and feel inconsistent despite representing the same concept ("when does this meter reset?").

## Goal

Every reset-time label across the popover uses the same relative-duration format, with granularity scaled to the window size. Users can tell how long until reset at a glance, in a single visual style.

## Design

### Unified relative-duration formatter

Replace `resetTimeString()` with one formatter that covers all window sizes. Remove `shortResetString()` and the `shortDateFormatter` static property entirely.

Tiered output (largest applicable tier wins). Every output is a two-unit composite — no one-unit fallbacks, no special-case strings:

| Interval to reset | Output   | Localization key                         |
| ----------------- | -------- | ---------------------------------------- |
| `≥ 24h`           | `3d 4h`  | `time.daysHours %lld %lld` (**new**)     |
| `< 24h`           | `2h 30m` | `time.hoursMinutes %lld %lld` (existing) |

Both tiers always render both units even when the smaller is zero (`3d 0h`, `2h 0m`, `0h 45m`, `0h 0m`). Keeping a single two-unit style across the whole lifecycle of a countdown — including after it hits zero — is an explicit design choice: labels should never change shape, only values. The `time.now` and `time.minutes` keys become unreachable under this rule and are removed.

Negative intervals (reset already elapsed, clock drift) are clamped to zero so the formatter still emits `0h 0m` rather than a negative value.

### Unified label

Both sections use the existing `usage.resetsIn %@` key:

- 5-hour row: `Resets in 2h 30m` (unchanged).
- 7-day rows (Total / Opus / Sonnet): replaces `· resets Thu`.

Keep the leading `·` bullet on the 7-day rows so they remain visually separated from the percentage (`Total … 75% · Resets in 3d 4h`). This preserves the current layout structure — label | % | · reset — which is what makes the slim row scannable.

Implementation: the bullet is a pure visual separator, rendered in Swift as `Text(verbatim: "· ")` followed by the `Text("usage.resetsIn \(…)")` — two adjacent `Text` views in the same `HStack`, not a new localization key. This keeps the bullet out of translated strings while letting the "Resets in" copy stay localized in one place (`usage.resetsIn %@`).

### Localization changes

**Add** to `en.lproj/Localizable.strings`:

```
"time.daysHours %lld %lld" = "%1$lldd %2$lldh";
```

**Add** to `ru.lproj/Localizable.strings`:

```
"time.daysHours %lld %lld" = "%1$lldд %2$lldч";
```

**Delete** from both files:

```
"usage.resetsOn %@" = "· resets %@";
"usage.resetsOn %@" = "· сброс %@";
"time.now" = "now";
"time.now" = "сейчас";
"time.minutes %lld" = "%lldm";
"time.minutes %lld" = "%lldм";
```

(Four removals per file — the `usage.resetsOn` key plus the two now-unreachable `time.*` keys.)

### Call-site changes (`UsageDetailView.swift`)

1. `fiveHourSection` — unchanged call site; the formatter it calls gets richer output handling.
2. `slimBar` — replaces the `"usage.resetsOn \(shortResetString(date))"` text with a formatted string that prefixes `· ` to the unified formatter's output. The `Text` uses the same `usage.resetsIn %@` key so copy changes are localized in one place.
3. Delete `shortResetString(_:)` and the `shortDateFormatter` static (lines 254–265).

## Non-goals

- No changes to colors, bar heights, or layout spacing.
- No changes to the API response model (`WindowUsage.resetsAt`) or parsing.
- No test additions. The formatter is a private view helper; existing tests (`UsageModelTests`, `AppStateTests`) don't cover view-level formatting, and this change doesn't alter that contract.

## Edge cases

- **Interval exactly 0 or negative** — clamped to zero, renders `0h 0m`. Replaces the previous `now` output; the shape of the label stays constant so sibling UI doesn't jump when a countdown expires.
- **Sub-minute interval** — `Int(interval) / 60` truncates to 0, renders `0h 0m`. Acceptable: the user sees the window has effectively reset.
- **Exact multiples** — `3d 0h`, `2h 0m`, `0h 45m`, `0h 0m` are all valid outputs. There is no one-unit output anywhere in the system.
- **Missing `resetsAt`** — the 7-day `slimBar` already guards with `if let date = resetDate`, so nil simply omits the reset suffix. Unchanged.
- **Locale** — Russian localization shipped with matching keys; other locales are not currently supported by the project.

## Files touched

- `Sources/ClaudeBarUI/Views/UsageDetailView.swift` — formatter unification, call-site update, dead-code removal.
- `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` — add `time.daysHours`; remove `usage.resetsOn`, `time.now`, `time.minutes`.
- `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` — same.
