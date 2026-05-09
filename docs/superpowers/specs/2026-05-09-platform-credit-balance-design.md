# Platform API Credit Balance — Design

**Date:** 2026-05-09
**Status:** Reverted 2026-05-09 — central auth assumption invalidated. See "Post-mortem" at the end of this document.
**Scope:** Surface the user's prepaid API credit balance from `platform.claude.com` inside the existing popover, alongside the claude.ai usage display.

---

## Problem

The popover shows claude.ai subscription usage (5h/7d windows, optional Max-tier extra credits) but says nothing about the user's prepaid Anthropic API credit balance — the dollar amount visible at `platform.claude.com/settings/billing`. Users who consume both products today have to switch to the browser to check API credits.

Anthropic does **not** expose a public endpoint for remaining balance. The published Admin API (`/v1/organizations/cost_report`, `/v1/organizations/usage_report/messages`) reports historical spend, not the prepaid wallet balance, requires an admin key, and is unavailable for individual accounts. The SDK feature request for an `/account_details` or `/balance` endpoint ([anthropic-sdk-python#505](https://github.com/anthropics/anthropic-sdk-python/issues/505)) is closed as "not planned." A `claude-code` issue requesting the same value through statusline also remains open ([claude-code#47574](https://github.com/anthropics/claude-code/issues/47574)).

## Evidence — empirical endpoint discovery

Captured from `platform.claude.com/settings/billing` Network panel and confirmed by direct cURL:

### Org listing

```
GET https://platform.claude.com/api/organizations
Cookie: sessionKey=<existing claude.ai sessionKey>
```

Returns an array of orgs the session has access to. Per-org fields include `uuid`, `name`, `capabilities`, `billing_type`, `rate_limit_tier`, plus a large `settings` blob we can ignore. Real captured shape (one user, three orgs):

| `uuid` | `name` | `capabilities` | `billing_type` | Has prepaid balance? |
|---|---|---|---|---|
| `4f4dee87…` | `…'s Organization` | `claude_pro`, `chat` | `stripe_subscription` | ❌ — Pro subscription, no API |
| `8bc28b46…` | `Vova's Individual Org` | **`api`**, `api_individual` | `api_evaluation` | ✅ |
| `72279f56…` | `Axveer` | `raven`, `chat` | `stripe_subscription` | ❌ — Team subscription, no API |

Discovery rule: an org has a prepaid balance iff `capabilities` contains `"api"`.

### Balance

```
GET https://platform.claude.com/api/organizations/{uuid}/prepaid/credits
Cookie: sessionKey=<existing claude.ai sessionKey>
```

Returns:

```json
{
  "amount": 189,
  "currency": "USD",
  "auto_reload_settings": null,
  "pending_invoice_amount_cents": null,
  "last_paid_purchase_cents": null
}
```

`amount` is in cents (189 ≡ $1.89, confirmed against the browser-rendered balance; the sibling `*_cents` fields confirm the unit). For an org without API capabilities the same endpoint returns HTTP 200 with `permission_error` "Invalid authorization for organization" — i.e. auth is valid but the requested org has no credits.

### Auth

The existing claude.ai `sessionKey` is accepted by `platform.claude.com` because both hosts share the `.claude.com` parent cookie domain. **No second Keychain entry, no second user setup flow is required.**

## Decisions

1. **Auth model: reuse the existing `sessionKey`.** Pass it as `Cookie: sessionKey=…` to `platform.claude.com` exactly as the existing `ClaudeAPIClient` does for `claude.ai`. No new credential storage, no new Settings UI, no new "session expired" recovery path beyond the one we already have.

2. **API org discovery:** call `GET https://platform.claude.com/api/organizations`, filter by `capabilities.contains("api")`, take the first match as the authoritative API org for the session. Cache its UUID on `AppState` for the lifetime of the session. Re-discover only on (a) sign-in, or (b) a `permission_error` response from `/prepaid/credits`. The user's claude.ai org list (from `claude.ai/api/organizations`) is **not** reused — the platform org space is queried separately to keep the feature decoupled from the org switcher.

3. **Refresh cadence: piggyback on the existing `pollTimer`.** Each `refreshUsage()` cycle additionally fetches the platform balance in parallel with `/usage`. Cost: one extra HTTP round-trip per poll (~250 bytes response). Keeps the data model simple (`platformCredits` updates in lockstep with `usage`) and avoids a second timer.

4. **Multi-API-org case: not supported in v1.** The first API org found wins. If the user has multiple API orgs (rare; e.g. an individual eval org plus a team org with `api` capability), the popover shows the first one's balance. A `// TODO` comment in the resolver flags the deferred decision.

5. **Display surface: popover only.** A new `apiCreditsSection` is inserted into `UsageDetailView` directly **after** the existing `extraUsageSection`. The menu bar text (currently `47%`) is **unchanged** — balance is "I should top up sometime this week" data, not "decide my next prompt" data.

6. **Hidden when not applicable:** if the user has no API org, or if the balance fetch has never succeeded for this session, the section is omitted entirely (zero vertical space, no placeholder). Mirrors how `extraUsageSection` is conditional on `extra.isEnabled`.

7. **Stale handling:** if a previously-successful balance fetch is followed by a failed one, keep displaying the last known value with reduced opacity (matching the existing `lastUpdated` pattern). Do not show error text inline — the existing global error banner remains the surface for "something is wrong."

8. **Currency formatting:** use `Foundation.Locale.current` with the response `currency` field. For an unknown/missing currency, fall back to `"USD"`. Cents → dollars conversion is `Double(amount) / 100.0`.

9. **`amount` unit: trust the observation that it is cents.** The sibling `*_cents` field naming corroborates. If Anthropic ever ships a response where `amount` is dollars-as-decimal-string (the same shape the cost-report endpoints use), the displayed value would be off by 100×. Acceptable risk for v1; the ratio is large enough that it would be noticed immediately.

## Changes

### `Sources/ClaudeBarUI/Models/UsageModel.swift` (or a new `PlatformCredits.swift`)

New model. Co-locating with `UsageModel` keeps API response types in one file; if the file grows, split in the implementation plan.

```swift
public struct PlatformCredits: Codable, Equatable {
    /// Balance in the smallest currency unit (cents for USD).
    public let amountCents: Int
    public let currency: String

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount"
        case currency
    }

    /// Decimal value for display, e.g. 189 → 1.89.
    public var amount: Double { Double(amountCents) / 100.0 }

    /// Locale-formatted display string (e.g. "$1.89", "€1.89").
    /// Implementation: Swift's `Decimal.FormatStyle.Currency(code:)` keyed off
    /// `currency` with `Locale.current` for grouping/decimal symbols.
    public func formatted(locale: Locale = .current) -> String
}
```

### `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`

Add platform-side request builders, parsers, and one fetch method. Mirrors the existing claude.ai pattern (separate request builder + static parser + async fetch wrapper) so tests can exercise parsing without network.

```swift
extension ClaudeAPIClient {
    private static let platformBaseURL = "https://platform.claude.com"

    public static func buildPlatformOrganizationsRequest(sessionKey: String) throws -> URLRequest { /* … */ }
    public func buildPlatformCreditsRequest(platformOrgId: String) throws -> URLRequest { /* … */ }

    public static func parsePlatformOrganizationsResponse(data: Data) throws -> [Organization] { /* … */ }
    public static func parsePlatformCreditsResponse(data: Data) throws -> PlatformCredits { /* … */ }

    /// Discover the user's API org and fetch its prepaid credit balance.
    /// Returns nil when no org with `api` capability exists.
    public static func fetchPlatformCredits(sessionKey: String) async throws -> PlatformCredits? { /* … */ }
}
```

The existing `Organization` struct is reused for the platform org list — its `uuid`, `name`, `capabilities` fields are the only ones consumed; extra fields in the response are ignored by the decoder.

### `Sources/ClaudeBarUI/Models/AppState.swift`

Add one observable property and extend `refreshUsage()` to fetch credits in parallel with `/usage`.

```swift
@MainActor
class AppState {
    // … existing fields …
    public private(set) var platformCredits: PlatformCredits?
    private var cachedPlatformOrgId: String?       // session-scoped cache
}
```

In `refreshUsage()`, after the existing usage fetch, run the credits fetch in a sibling `Task` so a slow or failing platform call never delays the usage display:

```swift
Task { [weak self, sessionKey] in
    let credits = try? await ClaudeAPIClient.fetchPlatformCredits(sessionKey: sessionKey)
    await MainActor.run {
        guard let self, self.sessionKey == sessionKey else { return }
        if let credits { self.platformCredits = credits }   // keep stale on failure
    }
}
```

Clear `platformCredits` on sign-out (alongside `usage`, `organizationDetails`, etc.) and on session-expired.

### `Sources/ClaudeBarUI/Views/UsageDetailView.swift`

Add `apiCreditsSection` and render it after the extra-usage block:

```swift
if let credits = state.platformCredits {
    Divider()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    apiCreditsSection(credits)
}
```

Visually consistent with the existing rows: small-caps section title (localized "API Credits"), value on the right in tabular-numeric font, matching the typography of the 5h / 7d / Extra Credits rows already in `UsageDetailView`. Stale state (last fetch failed but value retained) is conveyed by reduced opacity on the value (`.opacity(0.5)` or similar — exact tone deferred to the implementation plan).

### Localization

`Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`:

```
"section.apiCredits" = "API Credits";
```

`Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`:

```
"section.apiCredits" = "API кредиты";
```

(Russian convention in this project: tier names stay English, but section labels translate. "API кредиты" matches the existing tone.)

### `Tests/`

- `PlatformCreditsTests.swift` (new) — decoding fixture from the captured response; `formatted(locale:)` against `en_US` (`"$1.89"`) and `ru_RU` (`"1,89 $"`); zero-balance, missing-currency-fallback, large-balance (`amount: 1234567` → `$12,345.67`).
- `ClaudeAPIClientTests.swift` (extend) — `parsePlatformOrganizationsResponse` against a fixture containing the three real-shape orgs; ensure the decoder ignores the large `settings` blob; `fetchPlatformCredits` returns nil when no org has `api` capability.
- `AppStateTests.swift` (extend) — after `refreshUsage()`, `platformCredits` is populated when the (mocked) network returns a valid balance; previous balance is preserved when a follow-up fetch fails; cleared on `signOut()`.

## Behaviour after change

| Account state | Popover before | Popover after |
|---|---|---|
| User has only Pro/Team orgs (no `api` capability) | usage rows | usage rows *(unchanged — section hidden)* |
| User has API org with $1.89 balance | usage rows | usage rows + **API Credits — $1.89** |
| User has API org with $0.00 balance | usage rows | usage rows + **API Credits — $0.00** |
| Balance fetch transiently fails after a success | last known balance | last known balance, **dimmed** |
| Session expired (claude.ai 401) | error banner | error banner *(unchanged — single recovery path)* |
| Multiple API orgs | n/a | first API org's balance shown; second org silently ignored |

## Non-goals

- Surfacing balance in the menu bar text. The 5h utilization remains the sole menu-bar value.
- Low-balance threshold warnings (color shift, glyph). Nice-to-have for a follow-up; not v1.
- Multi-API-org UI (list, sum, switcher). Defer until a real user reports the need.
- Auto-reload status / `pending_invoice_amount_cents` / `last_paid_purchase_cents` display. The response carries them; v1 only consumes `amount` + `currency`.
- Showing claude.ai-side cost spend (`/v1/organizations/cost_report`). That endpoint requires an Admin API key, is unavailable for individual accounts, and reports a different concept (spend, not balance).
- Configurable refresh cadence. Same `pollInterval` as usage.
- Independent platform-side "session expired" UI. The shared `sessionKey` means a 401 on either host already triggers the existing `handleSessionExpired()` path.

## Risks and mitigations

- **`platform.claude.com` endpoints are undocumented.** Anthropic could rename the path, change the response shape, or invalidate the shared cookie strategy at any time — same risk class as the existing `claude.ai` integration. Mitigation: failures are silent (section hidden, usage display unaffected); tests cover the parser against captured fixtures so a shape change is caught locally before release.
- **`amount` unit assumption.** The unit is empirical, not documented. If the API ever returns `amount` as a decimal string of dollars (the cost-report convention), v1 displays `$189.00` instead of `$1.89`. Mitigation: PlatformCreditsTests asserts the decoded value against a known-good fixture; a CI run would catch a regression once a captured response changes.
- **Multi-API-org silent loss.** A future user with two API orgs sees only one balance and may assume the other doesn't exist. Mitigation: emit a `os_log` warning when more than one API org is found; revisit UI in a follow-up if the report comes in.
- **Permission-error 200 responses.** The endpoint returns HTTP 200 with a JSON error body when the org isn't authorized. The parser must distinguish — decode `permission_error` shape and treat as "no credits for this org" rather than as a successful balance. Implementation plan covers this in the parser.
- **Cookie domain change.** If Anthropic ever scopes the `sessionKey` cookie host-only, `platform.claude.com` requests would fail with a generic 401. Mitigation: same as session-expired handling — section hidden, usage display unaffected.

## Acceptance criteria

1. With a session that has at least one org carrying the `api` capability, opening the popover shows an **API Credits** row with the locale-formatted balance directly below the existing usage sections (and below the Extra Credits section when present).
2. With a session that has only Pro/Team orgs, no API Credits row appears and no extra HTTP error surfaces.
3. The menu bar text remains the 5h utilization percentage, byte-for-byte identical to current output.
4. A balance fetch failure after at least one prior success retains the displayed value with reduced opacity; usage display is unaffected.
5. On sign-out, `platformCredits` is cleared and the section disappears immediately.
6. New tests in `PlatformCreditsTests.swift` and the extensions to `ClaudeAPIClientTests` / `AppStateTests` pass; existing 120 tests remain green.

## Post-mortem (2026-05-09): not shipped — auth assumption invalidated

The plan (commit `c63a8e7`) was implemented in full across six commits (later reverted). All 134 tests passed. On the live smoke test against the author's account, `/api/organizations` returned 200 with the expected three orgs (one carrying the `api` capability) — but `/api/organizations/{uuid}/prepaid/credits` returned **403** with the same cookie.

Root cause: this spec's central assumption — *"the same `sessionKey` cookie unlocks both `claude.ai` and `platform.claude.com` because both share the parent `.claude.com` cookie domain"* — was wrong. There are **two distinct cookies named `sessionKey`**:

- One issued by `claude.ai` on the parent domain `.claude.com` (the one this app stores in Keychain after the user pastes from claude.ai DevTools).
- One issued by `platform.claude.com` scoped host-only to that subdomain (set when the user logs into the developer console).

When a browser visits `platform.claude.com`, RFC 6265 makes it send the host-specific cookie in preference to the parent-domain one. The captured cURL the user pasted during brainstorming therefore showed only the platform-scoped value, masking the dual-cookie reality. Both keys share the prefix `sk-ant-sid02-…` so they look identical at a glance.

Empirical evidence (from the smoke test, both keys belonging to the same authenticated user):

| Cookie | `/api/organizations` | `/api/organizations/{id}/prepaid/credits` |
|---|---|---|
| claude.ai-scoped (`-UOxn…`) | 200 | **403** |
| platform-scoped (`-bhn…`) | n/a tested | 200 |

The discovery endpoint is more permissive than the credits endpoint — it accepts the claude.ai-scoped key — which is what made the architecture look workable in the spec phase. Adding `anthropic-client-platform: web_console`, `Referer`, `routingHint`, and `lastActiveOrg` did not elevate the claude.ai-scoped key.

**Why we reverted instead of adapting:** to make this work the app would need a second Keychain entry, a second field in Settings, updated onboarding instructions ("now also paste the sessionKey from platform.claude.com"), and a new state machine for partial connections. That doubles the auth complexity for a single read-only display value (an API balance that's typically <$10). The cost/value math does not justify the change. If a future user requests the feature strongly enough, this spec and the reverted commits (visible in `c63a8e7..1100788` of the original branch history) document the path.
