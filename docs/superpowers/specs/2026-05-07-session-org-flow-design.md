# Session-key & Organization Flow Redesign

**Status:** Design approved, pending implementation plan
**Date:** 2026-05-07

## Problem

The current authentication flow conflates three distinct user intents into a single destructive `clearCredentials()` path:

1. **Refresh the session cookie** (cookie rotated, account/org unchanged) — most common
2. **Switch organization** (cookie fine, wrong org selected) — currently impossible without re-auth
3. **Sign out / change account** (rare, deliberate)

Today's `Settings → Update session key` button calls `clearCredentials()`, which wipes `sessionKey`, `orgId`, `organizations`, and `usage` in one shot. The app falls back to `SetupView` ("Setup ClaudeBar"), Settings disappears, and the user has to re-pick their org even though it never changed. The org list is also never persisted, so multi-org accounts have no way to switch organizations short of re-authenticating.

## Goals

- Updating the session key preserves `orgId` and Settings context when the org is still valid for the new key
- Multi-org accounts can switch organizations from the popover without re-entering the session key
- Session-expired recovery shows the user *which* org they're reconnecting to
- First-run setup remains a focused single-purpose flow

## Non-goals

- Multiple-account support (one ClaudeBar = one Anthropic account)
- OAuth integration (still requires manual sessionKey paste from DevTools)
- Org-list pre-validation before switching (we recover from 403 instead)

## State model

`AppState` gains the org list as persistent state, and the single `clearCredentials()` is split into intent-named methods.

```swift
public var organizations: [Organization] = []  // persisted to UserDefaults

// Transient state for the "wrong account" branch of updateSessionKey
public var pendingSessionKey: String?
public var pendingOrganizations: [Organization] = []
public var pendingOrgPick: Bool = false

public func signOut()                                       // wipe sessionKey, orgId, orgs, usage
public func updateSessionKey(_ key: String) async           // keep orgId if valid; swap sessionKey
public func switchOrganization(to org: Organization) async  // keep sessionKey; swap orgId
public func confirmPendingOrg(_ org: Organization) async    // commit pending sessionKey+org atomically
public func cancelPendingOrgPick()                          // discard pending state
```

**Storage layout:**
- **Keychain** (`credentials` blob, unchanged shape): `sessionKey\0orgId`
- **UserDefaults** (`com.claudebar.organizations`): JSON-encoded `[Organization]`

`organizations` loads synchronously in `loadCredentials()` so the picker is instant on launch. `isAuthenticated` continues to mean `sessionKey != nil && orgId != nil`.

The session-expired catch block becomes non-destructive: it nils `sessionKey`, `usage`, and `organizationDetails`, sets `error = .sessionExpired`, and **preserves `orgId` + `organizations`**. The Keychain blob is deleted, but the UserDefaults org cache stays.

## Flows

### Flow A — Update session key (Settings inline form)

1. User edits sessionKey field in Settings → taps Update
2. `updateSessionKey(newKey)` sets `isLoading`, calls `fetchOrganizations(sessionKey: newKey)`
3. On success:
   - If current `orgId` is in the new list → save `(newKey, orgId)` to Keychain, replace `organizations` cache (memory + UserDefaults), restart polling
   - If current `orgId` is **not** in the new list → **don't touch Keychain yet.** Hold the new sessionKey + new org list in transient state (`pendingSessionKey`, `pendingOrganizations`); set `pendingOrgPick = true`. Settings renders an inline picker ("This key belongs to a different account. Pick org:"). On pick → atomically save `(pendingSessionKey, pickedOrg.uuid)` to Keychain, commit `pendingOrganizations` to the cache, clear pending state. On cancel/close-settings → discard pending state, old credentials stay intact.
4. On `APIError.sessionExpired` (bad key) → inline error in form; no state mutation
5. User stays in Settings throughout — no view transition. Polling is paused while `pendingOrgPick == true` to avoid using a sessionKey that hasn't been committed.

### Flow B — Switch organization (header menu or Settings picker)

1. User picks an org from header `Menu` or Settings `Picker`
2. `switchOrganization(org)` saves `(sessionKey, org.uuid)` to Keychain
3. Clears stale `usage` and `organizationDetails` (tier may differ)
4. `startPolling()` triggers immediate `refreshUsage()`
5. No additional network call beyond the implicit refresh

### Flow C — Session expired recovery

1. `refreshUsage()` catches `APIError.sessionExpired` → nils `sessionKey`/`usage`/`organizationDetails`, **keeps** `orgId` + `organizations`, sets `error = .sessionExpired`
2. `PopoverView` routes to `SessionExpiredView` (existing condition: `!isAuthenticated && error == .sessionExpired`)
3. View renders "Reconnect *\<Org Name\>*" by looking up `orgId` in cached `organizations`
4. User pastes new key → enters Flow A; org-pick step skipped if `orgId` is in the new list (common case)

### Background org-list refresh

In `refreshUsage()`, after a successful poll, if `lastOrgListFetch` was > 1 hour ago, fetch organizations in the background and update UserDefaults. Cheap, keeps cache fresh, no user-visible latency.

## View changes

### `UsageDetailView` header — new org switcher

Above the rings, add a compact `Menu` button labeled with current org name + chevron. Menu contents:
- Other orgs from cache (each switches on tap, no confirmation)
- Divider
- "Update session key…" → opens Settings (`state.showingSettings = true`) with sessionKey field pre-focused
- "Settings…" → opens Settings normally

Single-org accounts: collapse `Menu` to a non-interactive `Text` label (no chevron). Same vertical real estate, no dead UI.

### `SettingsView` — Session group rewrite

Replace the single "Update session key" button with an inline form:

```
Session ──────────────────
● Connected as <Org Name>
Session key: [••••••••••••] [Update]
Organization: [<Org Name> ▾]
Sign out
```

- Session-key field shows masked dots until focused; `Update` calls `updateSessionKey`
- Picker is bound to cached `organizations`; `onChange` calls `switchOrganization`
- "Sign out" is a less-prominent text/secondary button at the bottom; calls `signOut()` and routes to `SetupView`
- All actions stay inside the Settings view — no transitions

### `SessionExpiredView` — title personalization

Title changes from "Session Expired" to "Reconnect *\<Org Name\>*". `OrgName` resolved by looking up `state.orgId` in `state.organizations`. Falls back to "Session Expired" if cache is empty (defensive). No org picker shown — sessionKey is the only field needed.

### `SetupView` — unchanged

First-run remains the single place where the org picker appears post-validation. This is the only entry point that wipes everything and starts fresh.

## Error handling

| Scenario | Effect |
|---|---|
| `updateSessionKey` → 401/403 | Inline error in form. State untouched. |
| `updateSessionKey` → 429 | Inline error "Too many attempts". State untouched. |
| `updateSessionKey` → network | Inline error with localized message. State untouched. |
| `switchOrganization` → Keychain write fails | Show error, revert in-memory `orgId`. |
| `switchOrganization` → subsequent refresh 401 | Standard session-expired path; new `orgId` retained for the reconnect screen. |
| Cached org list contains stale org user no longer belongs to | 403 on switch → standard session-expired flow. No pre-validation. |

The expired-session catch in `refreshUsage()` no longer calls `clearCredentials()`. Instead:

```swift
sessionKey = nil
usage = nil
organizationDetails = nil
error = .sessionExpired
// orgId, organizations: preserved
// Keychain blob: deleted
// UserDefaults org cache: untouched
```

## Testing

Existing 85 tests stay green. New tests use `makeState()` with the test Keychain (`com.claudebar.test`). For UserDefaults isolation, a parallel injection pattern: `AppState` accepts an `OrgListStore` protocol with a test-only in-memory implementation.

### `AppStateTests` (new)

- `testUpdateSessionKeyPreservesOrgIdWhenStillValid` — seed cache, mock new key returning the same org list, assert `orgId` unchanged after update
- `testUpdateSessionKeyPromptsPickerWhenOrgIdMissing` — mock new key returning a different org list, assert `pendingOrgPick == true`, `pendingSessionKey == newKey`, Keychain blob unchanged
- `testConfirmPendingOrgCommitsKeychainAndClearsPending` — from pending state, call `confirmPendingOrg`, assert Keychain has new sessionKey+orgId, pending state cleared
- `testCancelPendingOrgPickRevertsTransientState` — from pending state, call `cancelPendingOrgPick`, assert pending state cleared and old credentials intact
- `testUpdateSessionKeyBadKeyDoesNotMutateState` — mock 401, assert sessionKey/orgId/orgs unchanged, `error` set
- `testSwitchOrganizationSavesAndClearsStaleUsage` — assert `usage` and `organizationDetails` are nil after switch
- `testSessionExpiredPreservesOrgIdAndOrgs` — trigger `refreshUsage()` with 401 mock, assert `orgId` and `organizations` retained, `sessionKey == nil`
- `testSignOutWipesEverything` — assert sessionKey, orgId, orgs, usage, organizationDetails all cleared

### `OrganizationsCacheTests` (new)

- Round-trip encode/decode through the `OrgListStore` abstraction
- Migration test: pre-existing users with no cached orgs see empty array; org cache populates on first successful refresh

### View tests (ViewInspector)

- `SettingsView` shows current org name when authenticated; picker visible when `organizations.count > 1`
- `SessionExpiredView` renders "Reconnect *\<OrgName\>*" when `orgId` + cache populated; falls back to "Session Expired" otherwise
- `UsageDetailView` header renders `Menu` when `organizations.count > 1`, plain `Text` otherwise

**Target:** ~10 new tests, total ~95 passing.

## Migration

Existing users on launch:
1. Keychain blob loads as before → `sessionKey` + `orgId` populate
2. UserDefaults org cache is empty (key didn't exist) → `organizations = []`
3. First `refreshUsage()` succeeds → background org-list fetch populates cache
4. Header dropdown stays in single-org mode (plain `Text`) until cache populates

No destructive migration. No existing user is signed out. The first time a multi-org user opens the popover after upgrade, they'll have a single-org-style header for a few seconds until the background fetch completes, then the picker appears.

## Localization

New strings (English; ru.lproj parity required):

- `header.updateSessionKey` = "Update session key…"
- `header.settings` = "Settings…"
- `settings.connectedAs %@` = "Connected as %@"
- `settings.sessionKey` = "Session key:"
- `settings.organization` = "Organization:"
- `settings.signOut` = "Sign out"
- `session.reconnect %@` = "Reconnect %@"
- `update.wrongAccount` = "This key belongs to a different account. Pick org:"
- `update.badKey` = "Invalid session key"

Existing `setup.title`, `setup.instructions`, `session.expired`, `settings.updateSessionKey` retained (still used by SetupView and as fallbacks).

## Open questions

None blocking. Implementation plan should decide:
- Whether to gate the background org-list refresh behind a 1-hour TTL or just refresh on every successful poll (cheap call, may not need TTL)
- Exact `OrgListStore` protocol shape — minimal `load() -> [Organization]` / `save(_:)` is probably enough
