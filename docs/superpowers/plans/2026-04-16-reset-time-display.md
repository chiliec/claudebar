# Reset-Time Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the 5-hour and 7-day window reset labels behind a single relative-duration formatter so every reset label reads as `Resets in Xd Yh` / `Xh Ym` / `Xm` instead of the opaque weekday abbreviation (`resets Thu`).

**Architecture:** Single private formatter `resetTimeString(_:)` in `UsageDetailView` tiers the interval into days/hours/minutes and emits a localized string via three localization keys (`time.daysHours` new, `time.hoursMinutes` and `time.minutes` existing). Both `fiveHourSection` and `slimBar` (used by the 7-day Total / Opus / Sonnet rows) call the same formatter and render through the same `usage.resetsIn` localization key. The 7-day `slimBar` keeps its visual `· ` separator via inline Text concatenation, without introducing a new localization key.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Package Manager, macOS 14+. Localization via `.strings` files under `Sources/ClaudeBarUI/Resources/{en,ru}.lproj/`.

**Note on TDD:** The spec explicitly scopes this change as view-layer formatting and does not add tests (see `docs/superpowers/specs/2026-04-16-reset-time-display-design.md` — Non-goals). The formatter remains a private view helper, consistent with the codebase's existing pattern. This plan therefore verifies each step with `swift build` (compile-time correctness) and a final manual popover check (visual correctness) rather than unit tests.

**Worktree:** Not required for this change — it touches three files totaling ~30 lines. Execute on `main` unless you prefer isolation.

---

## File Structure

Files modified (no new files):

- `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` — add one key, remove one key.
- `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` — same.
- `Sources/ClaudeBarUI/Views/UsageDetailView.swift` — rewrite `resetTimeString`, update `slimBar` reset text, remove `shortResetString` and `shortDateFormatter`.

Exact locations in `UsageDetailView.swift` (as of commit `ee19c06`):

- `slimBar` resetDate block: lines 138-142
- `resetTimeString(_:)`: lines 245-252
- `shortDateFormatter` static: lines 254-261
- `shortResetString(_:)`: lines 263-265

---

## Task 1: Add `time.daysHours` localization key

**Files:**
- Modify: `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Add English string**

Open `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` and insert the new key alphabetically in the `time.*` group, directly above `"time.hoursMinutes %lld %lld"`:

```
"time.daysHours %lld %lld" = "%1$lldd %2$lldh";
```

The resulting `time.*` block should read:

```
"time.daysHours %lld %lld" = "%1$lldd %2$lldh";
"time.hoursMinutes %lld %lld" = "%1$lldh %2$lldm";
"time.minutes %lld" = "%lldm";
"time.now" = "now";
```

- [ ] **Step 2: Add Russian string**

Open `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` and insert the parallel key in the same position:

```
"time.daysHours %lld %lld" = "%1$lldд %2$lldч";
```

The resulting `time.*` block should read:

```
"time.daysHours %lld %lld" = "%1$lldд %2$lldч";
"time.hoursMinutes %lld %lld" = "%1$lldч %2$lldм";
"time.minutes %lld" = "%lldм";
"time.now" = "сейчас";
```

- [ ] **Step 3: Verify build still compiles**

Run: `swift build`
Expected: `Build complete!` with no errors. (The key is unused at this point — that is fine; `.strings` are resources, not compiled symbols, so unused keys do not warn.)

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings \
        Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings
git commit -m "i18n: add time.daysHours format key for days+hours duration"
```

---

## Task 2: Extend `resetTimeString` to handle the days tier

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift` (lines 245-252)

- [ ] **Step 1: Replace the formatter body**

Replace the existing `resetTimeString(_:)` method (currently lines 245-252):

```swift
    private func resetTimeString(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return String(localized: "time.now", bundle: .module) }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return String(localized: "time.hoursMinutes \(hours) \(minutes)", bundle: .module) }
        return String(localized: "time.minutes \(minutes)", bundle: .module)
    }
```

with the tiered version:

```swift
    private func resetTimeString(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return String(localized: "time.now", bundle: .module) }
        let totalSeconds = Int(interval)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return String(localized: "time.daysHours \(days) \(hours)", bundle: .module) }
        if hours > 0 { return String(localized: "time.hoursMinutes \(hours) \(minutes)", bundle: .module) }
        return String(localized: "time.minutes \(minutes)", bundle: .module)
    }
```

Key points:
- `86_400` is seconds per day (`24 * 60 * 60`). Underscore is a Swift numeric literal separator — purely cosmetic.
- Two-unit outputs always show both units when the larger is active: `3d 0h` is a valid output. This matches existing behavior of `time.hoursMinutes` (`2h 0m`).
- Tier check for `now` is strict `<= 0`; intervals in `(0, 60)` render `0m` (truncation), matching existing 5-hour behavior.

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: `Build complete!` with no errors. The 5-hour row still works (for intervals < 24h the new code path is identical); the 7-day rows still call `shortResetString` and are unchanged in this task.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift
git commit -m "feat(usage): add days tier to resetTimeString formatter"
```

---

## Task 3: Wire the unified formatter into the 7-day `slimBar`

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift` (lines 138-142)

- [ ] **Step 1: Replace the resetDate text block inside `slimBar`**

Find this block in `slimBar(_:utilization:resetDate:color:)` (currently lines 138-142):

```swift
                if let date = resetDate {
                    Text("usage.resetsOn \(shortResetString(date))", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
```

Replace it with:

```swift
                if let date = resetDate {
                    (Text(verbatim: "· ") + Text("usage.resetsIn \(resetTimeString(date))", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
```

Why Text concatenation (`+`) rather than two separate `Text` views in the HStack:
- The enclosing `HStack` has default spacing (8pt). Two sibling `Text` views would render as `·  Resets in 3d 4h` with a visible gap.
- SwiftUI's `Text + Text` operator produces a single inline text run — "· Resets in 3d 4h" renders as one word-wrapped piece.
- `Text(verbatim:)` prevents the bullet from being interpreted as a localization key lookup.

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: `Build complete!`. `shortResetString` is still defined (dead code warnings are not errors); it will be removed in Task 4.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift
git commit -m "feat(usage): render 7-day reset labels via unified duration formatter"
```

---

## Task 4: Remove dead code (`shortResetString`, `shortDateFormatter`)

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift` (lines 254-265 pre-change)

- [ ] **Step 1: Delete the static formatter and helper**

After Task 3 the only remaining caller of `shortResetString` was the `slimBar` block. Remove these lines entirely (currently 254-265, including the blank line between them):

```swift
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        if let langCode = Bundle.module.preferredLocalizations.first {
            formatter.locale = Locale(identifier: langCode)
        }
        return formatter
    }()

    private func shortResetString(_ date: Date) -> String {
        Self.shortDateFormatter.string(from: date)
    }
```

The file's remaining structure after this removal: `resetTimeString(_:)` is the last method inside `UsageDetailView`, immediately followed by the closing `}` of the struct and the `// MARK: - Liquid Glass Modifiers` comment.

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: `Build complete!` with no errors and no "unused declaration" warnings for the removed symbols (because they no longer exist).

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift
git commit -m "refactor(usage): remove obsolete weekday-only reset formatter"
```

---

## Task 5: Remove obsolete `usage.resetsOn` localization key

**Files:**
- Modify: `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Delete from English strings**

In `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`, delete the line:

```
"usage.resetsOn %@" = "· resets %@";
```

- [ ] **Step 2: Delete from Russian strings**

In `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`, delete the line:

```
"usage.resetsOn %@" = "· сброс %@";
```

- [ ] **Step 3: Confirm the key has no remaining references**

Run: `grep -rn "resetsOn" Sources Tests`
Expected: no output (empty result). If anything matches, stop and investigate — Task 3 should have removed the last call site.

- [ ] **Step 4: Verify build**

Run: `swift build`
Expected: `Build complete!`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings \
        Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings
git commit -m "i18n: remove unused usage.resetsOn key"
```

---

## Task 6: Manual verification in the running app

No automated test covers the popover formatting. Verify visually in both locales.

**Files:** none modified in this task.

- [ ] **Step 1: Launch the signed debug build**

Run: `./scripts/run.sh`
Expected: ClaudeBar icon appears in the menu bar. (If the script fails on code signing, see CLAUDE.md → "Code Signing".)

- [ ] **Step 2: Open the popover and inspect the 5-hour row**

Click the menu-bar icon. In the "5-Hour Window" section, on the right side of the progress bar:
- Expected when > 1h from reset: `Resets in Xh Ym` (e.g. `Resets in 2h 30m`).
- Expected when < 1h from reset: `Resets in Xm` (e.g. `Resets in 45m`).
- Expected at reset: `Resets in now` (rare to catch — acceptable if not observed).

No regression vs. pre-change behavior; this confirms Task 2 did not break the existing tier.

- [ ] **Step 3: Inspect the 7-day rows**

In the "7-Day Windows" section, each of Total / Opus / Sonnet:
- Expected: `<label>   <N>%  · Resets in Xd Yh` (e.g. `Total   42%  · Resets in 3d 4h`).
- The `· ` bullet sits directly before `Resets in` with no extra whitespace gap — a single inline text run.
- No weekday abbreviation (`Thu`, `Чт`) anywhere.

Visually compare the font weight / color of the `· Resets in …` label to the percentage beside it; the `.tertiary` foreground on the reset label should be noticeably dimmer than the `.secondary` percentage — unchanged from before.

- [ ] **Step 4: Switch system language to Russian and relaunch**

In macOS System Settings → General → Language & Region, add Russian and drag it above English, then quit and rerun `./scripts/run.sh`. Open the popover.
- Expected 5-hour: `Сброс через Xч Yм` (or `Xм` under 1 hour).
- Expected 7-day: `… · Сброс через Xд Yч` (e.g. `· Сброс через 3д 4ч`).
- No occurrence of `Чт` / `Пт` / etc.

Restore your preferred language order afterwards.

- [ ] **Step 5: Run the test suite as a safety net**

Run: `swift test`
Expected: all 65 tests pass. (This change does not touch any code covered by existing tests, so a pass is simply the "nothing else broke" signal.)

- [ ] **Step 6: Final commit — none needed**

All code changes are already committed (Tasks 1-5). This task is verification only. If you want to mark the plan complete in git history, an empty chore commit is acceptable but not required:

```bash
# Optional — only if your workflow expects a closing commit.
git commit --allow-empty -m "chore: verify reset-time display consistency"
```

---

## Task 7: Simplify to two-unit-only output

Added after Task 6 manual verification. Spec was amended to require every output be a two-unit composite — no `now`, no single-minute output. Every reset label is either `Xd Yh` or `Xh Ym`. See the updated spec for rationale.

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift` (the `resetTimeString(_:)` method)
- Modify: `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Simplify `resetTimeString(_:)`**

Replace the current implementation (tiered with `now` / `time.minutes` fallbacks) with:

```swift
    private func resetTimeString(_ date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)
        let totalSeconds = Int(interval)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        if days > 0 { return String(localized: "time.daysHours \(days) \(hours)", bundle: .module) }
        return String(localized: "time.hoursMinutes \(hours) \(minutes)", bundle: .module)
    }
```

Key changes vs. previous version:
- `max(0, date.timeIntervalSinceNow)` clamps past/zero intervals to 0 so they render `0h 0m` rather than triggering a special case.
- The `now` branch is removed.
- The `time.minutes`-only fallback is removed; sub-hour intervals now go through `time.hoursMinutes` with `hours = 0`, producing `0h Ym`.

- [ ] **Step 2: Remove now-unused localization keys**

In `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`, delete these two lines:

```
"time.minutes %lld" = "%lldm";
"time.now" = "now";
```

In `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`, delete:

```
"time.minutes %lld" = "%lldм";
"time.now" = "сейчас";
```

- [ ] **Step 3: Confirm no remaining references**

Run: `grep -rn "time.minutes\|time.now" Sources Tests`
Expected: no output.

- [ ] **Step 4: Verify build and tests**

Run: `swift build && swift test`
Expected: build succeeds; all 65 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift \
        Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings \
        Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings
git commit -m "refactor(usage): always emit two-unit reset durations"
```

---

## Verification Summary

After all tasks:

- `swift build` — succeeds.
- `swift test` — all 65 tests pass.
- `grep -rn "resetsOn\|shortResetString\|shortDateFormatter\|time\\.now\|time\\.minutes" Sources Tests` — no matches.
- Popover shows `Resets in Xd Yh` or `Xh Ym` uniformly across 5-hour and 7-day sections, in both English and Russian. No `now`, no bare `Xm`.
