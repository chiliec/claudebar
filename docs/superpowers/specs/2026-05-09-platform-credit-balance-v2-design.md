# Platform API Credit Balance (v2 — dual-auth) — Design

**Date:** 2026-05-09
**Status:** Approved (brainstorm) → ready for implementation plan
**Scope:** Surface the user's prepaid Anthropic API credit balance from `platform.claude.com` inside ClaudeBar, using a **separate** platform-scoped session that the user opts into from Settings. The claude.ai usage display is unchanged.

Supersedes the v1 spec at `docs/superpowers/specs/2026-05-09-platform-credit-balance-design.md` (reverted — see its post-mortem).

---

## Problem

The popover shows claude.ai subscription usage (5h / 7d windows, optional Max-tier extra credits) but says nothing about the user's prepaid Anthropic API credit balance — the dollar amount visible at `platform.claude.com/settings/billing`. Users who consume both products today have to switch to the browser to check API credits.

Anthropic does not expose a public balance endpoint (the published Admin API reports historical spend, requires an admin key, and is unavailable for individual accounts). The browser-only `platform.claude.com/api/organizations/{uuid}/prepaid/credits` is the only known source.

The v1 spec assumed the existing claude.ai `sessionKey` would authorize this endpoint via the shared `.claude.com` parent cookie domain. Empirical testing on 2026-05-09 disproved that — the endpoint requires a **second cookie** named `sessionKey` that is host-only to `platform.claude.com` and issued separately when the user logs into the developer console. v1 was reverted.

## Evidence — what changed since v1

The endpoint shapes are still as documented in v1. The only thing that changed is auth:

| Cookie | `/api/organizations` | `…/prepaid/credits` |
|---|---|---|
| claude.ai-scoped (parent `.claude.com`) | 200 | **403** |
| platform-scoped (host-only `platform.claude.com`) | 200 | 200 |

Both cookies share the prefix `sk-ant-sid02-…` so they look identical at a glance — captured cURLs from `platform.claude.com` show only the host-only value because of RFC 6265 cookie precedence. (Background: `memory/project_platform_credits_auth.md`.)

Implication: this feature **must** carry its own credential. There is no path to share the existing claude.ai key.

## Decisions

### 1. Two acquisition paths, one stored credential

Users obtain a platform `sessionKey` through either:

- **One-tap connect** — embedded WKWebView opens `https://platform.claude.com/login`; on successful login the app reads the `sessionKey` cookie from the webview's cookie store and saves it.
- **Manual paste** — disclosure section accepts a pasted `sessionKey` value (same recovery path as the existing claude.ai key).

Both paths write to the same single Keychain slot. Downstream (`AppState`, refresh, fetch, render) is identical regardless of how the credential was obtained.

### 2. Strictly opt-in — no onboarding changes

Existing setup flow (`SetupView` → claude.ai sessionKey paste) is untouched. The platform credential is acquired **on demand only**, from a new section in `SettingsView`. First-run users see no nudges, no extra steps, no mention of API balance unless they open Settings.

Rationale: the feature is read-only display value; users who don't have prepaid API credits should never be asked to do anything about it. The Pro/Team/Enterprise majority sees zero new UI.

### 3. Settings section: "Platform API"

Added to `SettingsView` directly below the existing claude.ai session block. Three render states:

```
┌────────────────────────────────────────────────┐
│ Platform API                                    │
│ ──────────────────────────────────────────────  │
│  Not connected · API balance hidden  [Connect]  │
│  ▾ Paste cookie manually                        │
└────────────────────────────────────────────────┘
```

```
┌────────────────────────────────────────────────┐
│ Platform API                                    │
│ ──────────────────────────────────────────────  │
│  Connected · $1.89          [Disconnect]        │
│  ▾ Replace key…                                 │
└────────────────────────────────────────────────┘
```

```
┌────────────────────────────────────────────────┐
│ Platform API                                    │
│ ──────────────────────────────────────────────  │
│  Disconnected · session expired   [Connect]     │
│  ▾ Paste cookie manually                        │
└────────────────────────────────────────────────┘
```

- **Disconnected** — `platformSessionKey == nil` and never connected (or explicitly disconnected). Shows `[Connect]` button + collapsed manual-paste disclosure.
- **Connected** — `platformSessionKey != nil` and the most recent fetch succeeded. Shows last known balance + `[Disconnect]` + collapsed "Replace key…" disclosure (same paste field, relabelled).
- **Stale / expired** — `platformSessionKey == nil` because the most recent fetch returned 401/403 and we cleared the key (see decision #8). Same shape as Disconnected but with explanatory subtitle.

The status line uses the existing `lastUpdated` typography. Balance is rendered with `Decimal.FormatStyle.Currency` keyed off the response's `currency` field.

### 4. `[Connect]` opens a modal sheet hosting WKWebView

- SwiftUI `.sheet(isPresented:)` over the Settings window. Approximate frame `640 × 720` — comfortable for the platform login form, leaves Settings visible behind the dimmer.
- Sheet contents: a thin `NSViewRepresentable` wrapper around `WKWebView` plus a small header with title ("Connect to platform.claude.com") and `[Cancel]`.
- Initial URL: `https://platform.claude.com/login`. If the user is already signed in elsewhere (Safari, etc.) and the platform redirects to `/dashboard`, that's fine — we capture the cookie either way.
- The webview uses an **isolated `WKWebsiteDataStore.nonPersistent()`** so:
  - Users always see a fresh login form (predictable UX, no surprise auto-login).
  - We never write Anthropic cookies into the user's Safari/system data store.
  - Cookies live only as long as the sheet is open; once captured into Keychain, the in-memory store is discarded.

### 5. Cookie capture via `WKNavigationDelegate.didFinishNavigation`

- After every successful navigation the delegate calls `WKWebsiteDataStore.nonPersistent().httpCookieStore.getAllCookies { … }`.
- It looks for a cookie matching: `name == "sessionKey"` AND `domain == "platform.claude.com"` (host-only — the parent-domain claude.ai cookie does not appear in this isolated store anyway).
- On match: save the cookie value to Keychain via `KeychainService`, set `AppState.platformSessionKey`, dismiss the sheet, and trigger an immediate balance refresh.
- No URL whitelisting, no JS injection, no DOM scraping. Cookie presence is the entire success signal — login form succeeds ⇒ cookie set ⇒ next navigation fires the delegate ⇒ we capture.

### 6. 90-second sheet timeout

A `Task.sleep(for: .seconds(90))` started when the sheet opens, cancelled on capture or manual dismiss. On expiry: dismiss the sheet, surface a transient "Connection timed out" message in the Settings section. This protects against:
- Login failures that never produce the cookie (user gives up but leaves the sheet open).
- Future Anthropic redirects that loop without ever writing the cookie we expect.

90 seconds is generous for entering credentials + 2FA but tight enough that an idle sheet doesn't hang around forever. Adjustable if needed; not configurable.

### 7. Manual paste — `▾ Paste cookie manually` (or `▾ Replace key…`)

Disclosure expands a single-line `SecureField` + `[Save]` button. Identical to the existing claude.ai recovery field in shape and validation:

- Trim whitespace.
- Reject empty.
- Reject values that don't start with `sk-ant-` (defensive — most users will paste correctly, but typos are common).
- On save: write to Keychain, set `AppState.platformSessionKey`, immediately call `refreshPlatformCredits()`. If the first fetch fails with 401/403, treat the same as decision #8 — clear the key, show "session expired".

Help text below the field: a short instruction with the URL the user should visit (`platform.claude.com/settings/billing`) and a hint that DevTools → Application → Cookies → `sessionKey` is where to copy from. Keep it terse — users who want this path already know what they're doing.

### 8. 401/403 from platform endpoints clears **only** the platform key

Critical: a session-expired response from `platform.claude.com` must NOT trigger the existing global `handleSessionExpired()` flow. That flow is owned by the claude.ai usage path and ejects the user back to `SetupView`. Platform expiry is local: clear `platformSessionKey`, render the section in the "Disconnected · session expired" state, leave usage display untouched.

Mechanism: the platform fetch path uses its own error mapping. `URLError` / non-2xx never bubbles into the existing `APIError.sessionExpired` branch.

### 9. Accept whatever account is in the webview, silently

No cross-account check between claude.ai and platform.claude.com. If the user's claude.ai session is tied to `babin@axveer.com` and they log into platform.claude.com as `someone-else@example.com`, the app shows that someone-else's API balance with no warning. Justification:

- Multi-account is rare among the target user base.
- Detecting the mismatch reliably would require an extra HTTP call (`/api/account` on each domain) and a UI for "you're logged in as X here vs Y there — proceed?". That cost outweighs the benefit for an opt-in display feature.
- If a user does mismatch and notices the wrong balance, `[Disconnect]` and reconnect is a one-click fix.

### 10. Refresh cadence: piggyback on `pollTimer` (when connected)

Each `refreshUsage()` cycle also calls `refreshPlatformCredits()` — but only when `platformSessionKey != nil`. When the user has not connected, the refresh is a no-op and zero extra HTTP traffic happens. Same one-extra-RTT cost as v1, scoped to opted-in users only.

### 11. Single API org assumption (carried over from v1)

Discovery via `GET https://platform.claude.com/api/organizations` — filter by `capabilities.contains("api")`, take the first match. Cache its UUID on `AppState` for the session. Re-discover on (a) connect, (b) any 200-with-`permission_error` response from `/prepaid/credits`. Multi-API-org users see the first one's balance; logged via `os_log` for future visibility.

### 12. Stale handling (carried over from v1)

If a previously-successful balance fetch is followed by a transient failure (network drop, 5xx), retain the last known value with reduced opacity. Only 401/403 specifically clears the key (decision #8) — generic failures keep the credential intact.

## Changes

### New file: `Sources/ClaudeBarUI/Services/PlatformAuthWebView.swift`

`NSViewRepresentable` wrapping `WKWebView` with the captured-cookie callback. Owns its `WKWebsiteDataStore.nonPersistent()` instance for the lifetime of the view.

```swift
import SwiftUI
import WebKit

@MainActor
public struct PlatformAuthWebView: NSViewRepresentable {
    public let onCapture: (String) -> Void           // sessionKey value
    public let onCancel: () -> Void                  // user-initiated or timeout

    public func makeNSView(context: Context) -> WKWebView { /* … */ }
    public func updateNSView(_ webView: WKWebView, context: Context) {}
    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        // didFinishNavigation → query httpCookieStore → match name=sessionKey domain=platform.claude.com → onCapture
    }
}
```

### New file: `Sources/ClaudeBarUI/Views/PlatformConnectSheet.swift`

The modal sheet UI: header (title + `[Cancel]`), the `PlatformAuthWebView`, and the timeout `Task`. Dismissed via either capture, cancel, or 90s expiry.

### Modified: `Sources/ClaudeBarUI/Views/SettingsView.swift`

Add `platformAPISection` rendering the three states from decision #3. The disclosure for manual paste / replace-key reuses the same paste-field component as the existing claude.ai recovery — extract a shared `SessionKeyPasteField` view if not already shared, otherwise duplicate (the file is small; a 30-line duplicate is fine).

### Modified: `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`

Same platform extension as the reverted v1 implementation, with one change: the request builders accept the **platform** sessionKey explicitly rather than reusing the claude.ai key. Headers identical to v1 (`anthropic-client-platform: web_console`, `Referer: https://platform.claude.com/settings/billing`).

```swift
extension ClaudeAPIClient {
    private static let platformBaseURL = "https://platform.claude.com"

    public static func buildPlatformOrganizationsRequest(platformSessionKey: String) throws -> URLRequest
    public static func buildPlatformCreditsRequest(platformSessionKey: String, platformOrgId: String) throws -> URLRequest

    public static func parsePlatformOrganizationsResponse(data: Data) throws -> [Organization]
    public static func parsePlatformCreditsResponse(data: Data) throws -> PlatformCredits

    /// Returns nil when no org has `api` capability, or when the auth/permission_error path resolves cleanly.
    /// Throws `PlatformAuthError.sessionExpired` on 401/403 — caller clears the platform key and renders "expired" state.
    public static func fetchPlatformCredits(platformSessionKey: String) async throws -> PlatformCredits?
}

public enum PlatformAuthError: Error {
    case sessionExpired                    // 401/403 — clear platform key only, do NOT touch claude.ai key
    case noApiOrg                          // 200 listing but no org has `api` capability
}
```

### Modified: `Sources/ClaudeBarUI/Models/UsageModel.swift` (or new `PlatformCredits.swift`)

Same `PlatformCredits` struct as v1: `amountCents: Int`, `currency: String`, `formatted(locale:) -> String`.

### Modified: `Sources/ClaudeBarUI/Models/AppState.swift`

```swift
@MainActor
class AppState {
    // existing fields …

    public private(set) var platformSessionKey: String?       // nil when not connected
    public private(set) var platformCredits: PlatformCredits?
    public private(set) var platformCreditsIsStale: Bool = false
    private var cachedPlatformOrgId: String?                  // session-scoped cache

    public func connectPlatform(sessionKey: String) async    // save to Keychain, refresh
    public func disconnectPlatform()                          // delete from Keychain, clear state
    public func refreshPlatformCredits() async               // no-op if platformSessionKey == nil
}
```

`KeychainService` account name: `"platform_credentials"` (alongside the existing `"credentials"` slot used by the claude.ai key + orgId).

`refreshUsage()` gets one new line at the end:

```swift
Task { [weak self] in await self?.refreshPlatformCredits() }
```

### Modified: `Sources/ClaudeBarUI/Views/UsageDetailView.swift`

Same `apiCreditsSection` insertion as v1 — gated on `state.platformCredits != nil`. Stale state (`platformCreditsIsStale == true`) renders with reduced opacity.

### Localization

`Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`:

```
"section.apiCredits"                  = "API Credits";
"settings.platformAPI"                = "Platform API";
"settings.platformAPI.notConnected"   = "Not connected · API balance hidden";
"settings.platformAPI.connected"      = "Connected";
"settings.platformAPI.expired"        = "Disconnected · session expired";
"settings.platformAPI.connect"        = "Connect";
"settings.platformAPI.disconnect"     = "Disconnect";
"settings.platformAPI.pasteManually"  = "Paste cookie manually";
"settings.platformAPI.replaceKey"     = "Replace key…";
"settings.platformAPI.connectSheet.title"   = "Connect to platform.claude.com";
"settings.platformAPI.connectSheet.timeout" = "Connection timed out";
```

Russian counterparts in `ru.lproj/Localizable.strings`. (Translations deferred to implementation plan; "Platform API" stays English to match the existing tier-name convention in this codebase.)

### Tests

- `PlatformCreditsTests.swift` — decoding, currency formatting, stale rendering. (Same as v1.)
- `ClaudeAPIClientTests.swift` (extend) — `parsePlatformOrganizationsResponse`, `parsePlatformCreditsResponse`, `fetchPlatformCredits` distinguishes 401/403 → `.sessionExpired` from the permission-error 200 → `.noApiOrg`.
- `AppStateTests.swift` (extend) —
  - `connectPlatform(sessionKey:)` writes to Keychain and triggers a refresh.
  - `disconnectPlatform()` clears Keychain, `platformSessionKey`, `platformCredits`, `cachedPlatformOrgId`.
  - 401/403 from platform fetch clears `platformSessionKey` but does **not** clear `sessionKey` / `orgId` / `usage` (regression guard for decision #8).
  - `refreshUsage()` is a no-op for the platform path when `platformSessionKey == nil` (no spurious HTTP attempts).
- `PlatformAuthWebViewTests.swift` (new) — pure-cookie-matching unit tests on the coordinator's filter logic (`name == "sessionKey"`, `domain == "platform.claude.com"`); does **not** instantiate WKWebView (impractical in test target). The webview/cookie-store integration is exercised by manual smoke test only.

## Behaviour after change

| Account state | Settings | Popover |
|---|---|---|
| Never connected | "Not connected · API balance hidden" + `[Connect]` | usage rows *(unchanged)* |
| Connected, balance $1.89 | "Connected · $1.89" + `[Disconnect]` | usage rows + **API Credits — $1.89** |
| Connected, $0.00 | "Connected · $0.00" + `[Disconnect]` | usage rows + **API Credits — $0.00** |
| Connected, fetch transiently fails | last known balance, dimmed | last known balance, dimmed |
| Connected, fetch returns 401/403 | "Disconnected · session expired" + `[Connect]` | API Credits row disappears |
| Connected, no API org found | "Connected" with no balance line; `os_log` warning | API Credits row hidden |
| User disconnects | "Not connected · API balance hidden" + `[Connect]` | API Credits row disappears |
| claude.ai session expires | unchanged (platform state independent) | existing session-expired flow |

## Non-goals

- First-run / onboarding integration. Settings is the only entry point.
- Menu bar text inclusion. Menu bar shows 5h utilization, byte-for-byte unchanged.
- Multi-API-org UI (list, sum, switcher). First match wins; warning logged.
- Cross-account validation between claude.ai and platform.claude.com sessions. Decision #9.
- Auto-reload status / `pending_invoice_amount_cents` / `last_paid_purchase_cents` display. Response carries them; v2 only consumes `amount` + `currency`.
- Low-balance threshold warnings (color shift, glyph). Possible follow-up.
- Persisting webview cookies across launches. Decision #4 — non-persistent data store, by design.
- Configurable refresh cadence. Same `pollInterval` as usage.
- Independent platform-side polling timer. Piggybacks on `refreshUsage()`.
- Recovery UI for the WKWebView itself failing to load (offline, TLS error). Sheet shows blank with the cancel button — sufficient.

## Risks and mitigations

- **WKWebView cookie store is async / racey.** `getAllCookies` is callback-based; on `didFinishNavigation` we call it but the cookie may not yet be visible if Anthropic sets it from a later XHR. Mitigation: the delegate runs after **every** navigation transition, not just the first. Empirically `platform.claude.com/login` redirects to `/dashboard` after success, and the cookie is present by the time the dashboard navigation finishes. If observation proves this wrong, fall back to an additional `WKHTTPCookieStoreObserver` on `cookiesDidChange`.
- **Anthropic redirects to a different login page.** If `/login` ever redirects to a unified Claude SSO page, the cookie name and domain might differ. The capture filter only matches `name == "sessionKey"` AND `domain == "platform.claude.com"` — a different shape would simply never capture, leading to the 90-second timeout. Mitigation: timeout guards against silent hang; a future shape change is detectable from user reports of "Connect button doesn't work."
- **`platform.claude.com` API contract changes.** Same risk class as the existing claude.ai integration. Failures are silent (section returns to Disconnected); usage display unaffected.
- **Manual paste of the wrong key.** A user could paste their claude.ai key into the manual-paste field — it would 403 on the very first fetch and immediately render "session expired". Acceptable: the failure is fast and localised. The disclosure help text names the correct domain.
- **Cookie ACL / Keychain access.** New Keychain slot `platform_credentials` reuses the same `KeychainService` upsert pattern that already handles `errSecDuplicateItem` (the bug fixed in v0.0.10).
- **`amount` unit assumption.** Same as v1 — empirical that it's cents. Test fixture asserts the exact value.
- **Permission-error 200 responses.** Parser must distinguish — same handling as the reverted v1 implementation; tests cover both shapes.

## Acceptance criteria

1. With no platform key set, ClaudeBar's behaviour is byte-for-byte identical to v0.0.12 (no extra HTTP, no extra UI in the popover, no menu bar change). Settings shows the new "Platform API" section in the **Disconnected** state.
2. Clicking `[Connect]` opens a modal sheet hosting `platform.claude.com/login` in an isolated WKWebView. Successful login dismisses the sheet automatically and the section transitions to **Connected** with the live balance.
3. The captured `sessionKey` is stored in Keychain under account `platform_credentials` (separate from the existing `credentials` slot).
4. Pasting a valid platform `sessionKey` into the disclosure field saves it identically — same Keychain slot, same downstream refresh — and renders **Connected** within one poll cycle.
5. A 401/403 from `/prepaid/credits` clears `platformSessionKey` only; the claude.ai key, orgId, usage display, and global session state are untouched. Settings section transitions to **Disconnected · session expired**.
6. Clicking `[Disconnect]` deletes the platform Keychain entry, clears `platformSessionKey`, `platformCredits`, and `cachedPlatformOrgId`. The popover's API Credits row disappears immediately.
7. The webview's cookies are not persisted to disk and are not visible to Safari or other apps (verified by the use of `WKWebsiteDataStore.nonPersistent()`).
8. New and existing tests pass; the v0.0.12 test count of 120 grows by the platform-specific suite.
