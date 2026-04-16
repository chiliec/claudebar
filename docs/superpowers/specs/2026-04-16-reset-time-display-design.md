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

Tiered output (largest applicable tier wins):

| Interval to reset    | Output    | Localization key                        |
| -------------------- | --------- | --------------------------------------- |
| `≤ 0`                | `now`     | `time.now` (existing)                   |
| `≥ 24h`              | `3d 4h`   | `time.daysHours %lld %lld` (**new**)    |
| `≥ 1h` and `< 24h`   | `2h 30m`  | `time.hoursMinutes %lld %lld` (existing)|
| `< 1h`               | `45m`     | `time.minutes %lld` (existing)          |

Two-unit outputs (`3d 4h`, `2h 30m`) always render both units even when the smaller is zero (`3d 0h`, `2h 0m`). This matches the existing behavior of `time.hoursMinutes` and keeps the label width stable as the countdown ticks down.

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
```

### Call-site changes (`UsageDetailView.swift`)

1. `fiveHourSection` — unchanged call site; the formatter it calls gets richer output handling.
2. `slimBar` — replaces the `"usage.resetsOn \(shortResetString(date))"` text with a formatted string that prefixes `· ` to the unified formatter's output. The `Text` uses the same `usage.resetsIn %@` key so copy changes are localized in one place.
3. Delete `shortResetString(_:)` and the `shortDateFormatter` static (lines 254–265).

## Non-goals

- No changes to tier boundaries, colors, bar heights, or layout spacing.
- No changes to the API response model (`WindowUsage.resetsAt`) or parsing.
- No changes to the 5-hour section's existing behavior when interval < 1 hour (`45m`) or at zero (`now`).
- No test additions. The formatter is a private view helper; existing tests (`UsageModelTests`, `AppStateTests`) don't cover view-level formatting, and this change doesn't alter that contract.

## Edge cases

- **Interval exactly 0 or negative** — renders `now` via existing `time.now` key. This matches today's 5-hour behavior; the 7-day rows gain this behavior (currently they would still show the weekday of the past reset date).
- **Exact multiples** — `3d 0h`, `2h 0m`, `0m` are all valid outputs. `0m` replaces what used to be `now`? No — the tier check is strictly `> 0` for `now`, so a 30-second interval renders `0m` (truncation). Acceptable: it matches the existing `time.minutes` behavior for the 5-hour row.
- **Missing `resetsAt`** — the 7-day `slimBar` already guards with `if let date = resetDate`, so nil simply omits the reset suffix. Unchanged.
- **Locale** — Russian localization shipped with matching keys; other locales are not currently supported by the project.

## Files touched

- `Sources/ClaudeBarUI/Views/UsageDetailView.swift` — formatter unification, call-site update, dead-code removal.
- `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` — add `time.daysHours`, remove `usage.resetsOn`.
- `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` — same.
