# Platform API Credit Balance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the user's prepaid Anthropic API credit balance from `platform.claude.com` in the popover, directly after the existing Extra Credits section. Reuses the existing `claude.ai` `sessionKey` — no second auth flow.

**Architecture:** Three layers of changes. (1) New `PlatformCredits` value type and an extension on the existing `ClaudeAPIClient` that talks to `platform.claude.com/api/organizations` and `…/prepaid/credits`. (2) Three new properties on `AppState` (`platformCredits`, `platformCreditsIsStale`, `cachedPlatformOrgId`) plus a `refreshPlatformCredits(sessionKey:)` method called as a sibling `Task` from `refreshUsage()` so a slow/failing platform call never delays the usage display. (3) A new `apiCreditsSection` view in `UsageDetailView` rendered only when `state.platformCredits != nil`, dimmed when `platformCreditsIsStale == true`. The menu bar text is unchanged.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test` / `#expect`), Swift Package Manager, `URLSession` for HTTP.

**Spec:** `docs/superpowers/specs/2026-05-09-platform-credit-balance-design.md` (commit `ab796b9`)

---

## File Inventory

- **Modify:** `Sources/ClaudeBarUI/Models/UsageModel.swift` — append a new `PlatformCredits` struct after the existing `OrganizationDetails` struct (around line 135).
- **Modify:** `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift` — append new request builders, parsers, and fetch methods inside an `extension ClaudeAPIClient` block at the bottom of the file (after the existing `APIError`/`ISO8601DateFormatter` declarations).
- **Modify:** `Sources/ClaudeBarUI/Models/AppState.swift` — add three properties under `// MARK: - Usage State`, clear them in `signOut()` and `handleSessionExpired()`, add `refreshPlatformCredits(sessionKey:)` and pure state-transition helpers, call the new method as a sibling `Task` inside `refreshUsage()`.
- **Modify:** `Sources/ClaudeBarUI/Views/UsageDetailView.swift` — render `apiCreditsSection(credits)` after the existing `extraUsageSection(...)` block; declare the new private builder under the existing `extraUsageSection` definition.
- **Modify:** `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` — add `"section.apiCredits" = "API Credits";`.
- **Modify:** `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` — add `"section.apiCredits" = "API кредиты";`.
- **Modify:** `Tests/UsageModelTests.swift` — add four `PlatformCredits` decoder/formatter tests.
- **Modify:** `Tests/ClaudeAPIClientTests.swift` — add five tests for platform request builders and parsers (org list with `api` filter, `permission_error` 200, valid credits, missing currency).
- **Modify:** `Tests/AppStateTests.swift` — add five tests for the new state transitions (success sets value, failure-after-success marks stale, sign-out clears all platform state, expired session clears all platform state, no API org keeps everything nil).

No new files are created.

---

## Task 1: Add `PlatformCredits` model

The model holds the balance in cents (matching the API response), exposes a decimal accessor for math, and provides a locale-formatted display string. We reuse Swift's `Decimal.FormatStyle.Currency` so the symbol/grouping match the user's locale automatically.

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/UsageModel.swift` (append a new struct after `OrganizationDetails`, around line 135)
- Test: `Tests/UsageModelTests.swift` (append four new tests at the end of the suite, after `colorForUtilization` around line 230)

- [ ] **Step 1: Write the failing tests**

In `Tests/UsageModelTests.swift`, append the following four tests after `colorForUtilization`:

```swift
@Test func decodePlatformCreditsResponse() throws {
    let json = """
    {
      "amount": 189,
      "currency": "USD",
      "auto_reload_settings": null,
      "pending_invoice_amount_cents": null,
      "last_paid_purchase_cents": null
    }
    """.data(using: .utf8)!

    let credits = try JSONDecoder().decode(PlatformCredits.self, from: json)

    #expect(credits.amountCents == 189)
    #expect(credits.currency == "USD")
    #expect(abs(credits.amount - 1.89) < 0.0001)
}

@Test func decodePlatformCreditsZeroBalance() throws {
    let json = """
    { "amount": 0, "currency": "USD" }
    """.data(using: .utf8)!

    let credits = try JSONDecoder().decode(PlatformCredits.self, from: json)

    #expect(credits.amountCents == 0)
    #expect(credits.amount == 0.0)
}

@Test func platformCreditsFormattedUSEnglish() {
    let credits = PlatformCredits(amountCents: 189, currency: "USD")
    let formatted = credits.formatted(locale: Locale(identifier: "en_US"))
    // Expect "$1.89" — exact form depends on Foundation but symbol & magnitude must match
    #expect(formatted.contains("1.89"))
    #expect(formatted.contains("$"))
}

@Test func platformCreditsFormattedLargeAmount() {
    let credits = PlatformCredits(amountCents: 1_234_567, currency: "USD")
    let formatted = credits.formatted(locale: Locale(identifier: "en_US"))
    // 12,345.67 dollars
    #expect(formatted.contains("12,345.67"))
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter UsageModelTests.decodePlatformCreditsResponse`

Expected: build error — `cannot find 'PlatformCredits' in scope`. This is the "red" state for this task.

- [ ] **Step 3: Implement — add the `PlatformCredits` struct**

In `Sources/ClaudeBarUI/Models/UsageModel.swift`, append the following after the closing `}` of `OrganizationDetails` (around line 135), before the `SubscriptionTier` enum:

```swift
/// Prepaid credit balance for an Anthropic API (platform.claude.com) org.
/// `amountCents` is the smallest currency unit — for USD that is cents, for
/// EUR cents, etc. The API response uses field name `amount`; the `*_cents`
/// sibling fields confirm the unit.
public struct PlatformCredits: Codable, Equatable {
    public let amountCents: Int
    public let currency: String

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount"
        case currency
    }

    public init(amountCents: Int, currency: String) {
        self.amountCents = amountCents
        self.currency = currency
    }

    /// Decimal value for display, e.g. 189 → 1.89.
    public var amount: Double { Double(amountCents) / 100.0 }

    /// Locale-formatted display string (e.g. "$1.89", "1,89 €").
    public func formatted(locale: Locale = .current) -> String {
        let decimal = Decimal(amountCents) / 100
        return decimal.formatted(.currency(code: currency).locale(locale))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter UsageModelTests.decodePlatformCreditsResponse && swift test --filter UsageModelTests.decodePlatformCreditsZeroBalance && swift test --filter UsageModelTests.platformCreditsFormattedUSEnglish && swift test --filter UsageModelTests.platformCreditsFormattedLargeAmount`

Expected: all four PASS.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

Run: `swift test`

Expected: all tests pass (current count is 120; this task adds 4 → expect 124 green).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Models/UsageModel.swift Tests/UsageModelTests.swift
git commit -m "feat(credits): add PlatformCredits model"
```

---

## Task 2: Extend `ClaudeAPIClient` with platform request builders and parsers

We add four pure functions: two request builders (one for the org list, one for the credits endpoint) and two response parsers (org list, credits — where the credits parser distinguishes `permission_error` 200 responses from real successes). Network-free so they're trivially testable.

**Files:**
- Modify: `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift` (append a new `extension ClaudeAPIClient` block at the bottom of the file, after the `ISO8601DateFormatter` extension around line 146)
- Test: `Tests/ClaudeAPIClientTests.swift` (append five new tests at the end of the suite, after `parseOrganizationsResponse` around line 51)

- [ ] **Step 1: Write the failing tests**

In `Tests/ClaudeAPIClientTests.swift`, append the following tests after the existing `parseOrganizationsResponse` test:

```swift
@Test func buildPlatformOrganizationsRequest() throws {
    let request = try ClaudeAPIClient.buildPlatformOrganizationsRequest(sessionKey: "sk-test")

    #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations")
    #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
    #expect(request.httpMethod == "GET")
}

@Test func buildPlatformCreditsRequest() throws {
    let request = try ClaudeAPIClient.buildPlatformCreditsRequest(
        sessionKey: "sk-test",
        platformOrgId: "8bc28b46-d6dd-4982-a38a-66a11be1c437"
    )

    #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations/8bc28b46-d6dd-4982-a38a-66a11be1c437/prepaid/credits")
    #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
    #expect(request.httpMethod == "GET")
}

@Test func parsePlatformOrganizationsIgnoresExtraFields() throws {
    // Real captured response shape — note the large `settings` blob and many
    // fields the model doesn't consume. Decoder must ignore them gracefully.
    let json = """
    [
      {
        "id": 136002694,
        "uuid": "4f4dee87-d910-4390-ae54-b64ad23b9243",
        "name": "Personal",
        "settings": { "claude_console_privacy": "default_private", "allowed_invite_domains": null },
        "capabilities": ["claude_pro", "chat"],
        "billing_type": "stripe_subscription"
      },
      {
        "id": 151870534,
        "uuid": "8bc28b46-d6dd-4982-a38a-66a11be1c437",
        "name": "Vova's Individual Org",
        "settings": {},
        "capabilities": ["api", "api_individual"],
        "billing_type": "api_evaluation"
      }
    ]
    """.data(using: .utf8)!

    let orgs = try ClaudeAPIClient.parsePlatformOrganizationsResponse(data: json)

    #expect(orgs.count == 2)
    #expect(orgs[1].uuid == "8bc28b46-d6dd-4982-a38a-66a11be1c437")
    #expect(orgs[1].capabilities?.contains("api") == true)
}

@Test func parsePlatformCreditsHappyPath() throws {
    let json = """
    {
      "amount": 189,
      "currency": "USD",
      "auto_reload_settings": null,
      "pending_invoice_amount_cents": null,
      "last_paid_purchase_cents": null
    }
    """.data(using: .utf8)!

    let credits = try ClaudeAPIClient.parsePlatformCreditsResponse(data: json)

    #expect(credits != nil)
    #expect(credits?.amountCents == 189)
    #expect(credits?.currency == "USD")
}

@Test func parsePlatformCreditsReturnsNilOnPermissionError() throws {
    // The endpoint returns HTTP 200 with a permission_error body when the
    // session is valid but the requested org has no prepaid credits.
    let json = """
    {
      "type": "error",
      "error": {
        "type": "permission_error",
        "message": "Invalid authorization for organization",
        "details": { "error_visibility": "user_facing" }
      },
      "request_id": "req_011CarEk9gJt4F4znLHquZ25"
    }
    """.data(using: .utf8)!

    let credits = try ClaudeAPIClient.parsePlatformCreditsResponse(data: json)

    #expect(credits == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter ClaudeAPIClientTests.buildPlatformOrganizationsRequest`

Expected: build error — `type 'ClaudeAPIClient' has no member 'buildPlatformOrganizationsRequest'`. This is the "red" state.

- [ ] **Step 3: Implement — add the platform extension to `ClaudeAPIClient`**

In `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`, append the following after the existing `ISO8601DateFormatter` extension (after line 146):

```swift
// MARK: - platform.claude.com (prepaid API credits)

extension ClaudeAPIClient {
    private static let platformBaseURL = "https://platform.claude.com"

    public static func buildPlatformOrganizationsRequest(sessionKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(platformBaseURL)/api/organizations") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    public static func buildPlatformCreditsRequest(sessionKey: String, platformOrgId: String) throws -> URLRequest {
        guard let url = URL(string: "\(platformBaseURL)/api/organizations/\(platformOrgId)/prepaid/credits") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    public static func parsePlatformOrganizationsResponse(data: Data) throws -> [Organization] {
        // Reuses the existing Organization type; extra fields in the response
        // (id, settings, billing_type, etc.) are ignored by the decoder.
        return try JSONDecoder().decode([Organization].self, from: data)
    }

    /// Parse the prepaid credits response. Returns `nil` for the
    /// `permission_error` 200 body (session valid, org has no credits).
    public static func parsePlatformCreditsResponse(data: Data) throws -> PlatformCredits? {
        // Probe for an error envelope before attempting the success decode.
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable { let type: String }
            let type: String
            let error: Inner
        }
        if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           env.type == "error" {
            return nil
        }
        return try JSONDecoder().decode(PlatformCredits.self, from: data)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ClaudeAPIClientTests`

Expected: all `ClaudeAPIClientTests` (including the new five) pass.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`

Expected: all tests pass (124 from Task 1 → expect 129 green).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift Tests/ClaudeAPIClientTests.swift
git commit -m "feat(credits): add platform.claude.com request builders and parsers"
```

---

## Task 3: Add `fetchPlatformOrganizations` and `fetchPlatformCredits` network methods

Thin async wrappers around the request builders + parsers. They call `URLSession.shared.data(for:)`, validate the HTTP status with the existing `validateHTTPResponse` helper, and parse the body. Following the existing convention (see `fetchOrganizations`), these are not unit-tested in isolation — the parsers and request builders are.

**Files:**
- Modify: `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift` (extend the platform extension added in Task 2)

- [ ] **Step 1: Make the helper non-private so the platform extension can call it**

`validateHTTPResponse` is currently `private static` (around line 103). Change it to `internal static` (drop the `private`):

```swift
static func validateHTTPResponse(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
    }
    switch http.statusCode {
    case 200: return
    case 401, 403: throw APIError.sessionExpired
    case 429: throw APIError.rateLimited
    default: throw APIError.httpError(http.statusCode)
    }
}
```

- [ ] **Step 2: Add the fetch methods to the platform extension**

In `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`, append the following inside the `extension ClaudeAPIClient` block added in Task 2 (after `parsePlatformCreditsResponse`):

```swift
public static func fetchPlatformOrganizations(sessionKey: String) async throws -> [Organization] {
    let request = try buildPlatformOrganizationsRequest(sessionKey: sessionKey)
    let (data, response) = try await URLSession.shared.data(for: request)
    try validateHTTPResponse(response)
    return try parsePlatformOrganizationsResponse(data: data)
}

/// Returns `nil` when the org has no prepaid credits (permission_error 200).
/// Throws `APIError.sessionExpired` on 401/403 — the shared sessionKey is bad.
public static func fetchPlatformCredits(sessionKey: String, platformOrgId: String) async throws -> PlatformCredits? {
    let request = try buildPlatformCreditsRequest(sessionKey: sessionKey, platformOrgId: platformOrgId)
    let (data, response) = try await URLSession.shared.data(for: request)
    try validateHTTPResponse(response)
    return try parsePlatformCreditsResponse(data: data)
}
```

- [ ] **Step 3: Build to confirm compilation**

Run: `swift build`

Expected: build succeeds with no warnings. (No new tests in this task — the parsers and request builders covered by Task 2 already verify the behaviour these methods compose.)

- [ ] **Step 4: Run the full test suite**

Run: `swift test`

Expected: all tests still pass (count unchanged from end of Task 2: 129 green).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift
git commit -m "feat(credits): add fetchPlatformOrganizations and fetchPlatformCredits"
```

---

## Task 4: Add platform credit state to `AppState` (properties + clear-on-signout)

Three new observable properties, plus clearing them in `signOut()` and `handleSessionExpired()`. Pure state-transition helpers (`applyPlatformCreditsSuccess`, `markPlatformCreditsFetchFailed`) are added in Task 5 — this task only deals with the persistent state and lifecycle.

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift` (add properties under `// MARK: - Usage State` around line 30; modify `signOut()` around line 109 and `handleSessionExpired()` around line 123)
- Test: `Tests/AppStateTests.swift` (append two new tests after `saveAndLoadCredentials`, around line 95)

- [ ] **Step 1: Write the failing tests**

In `Tests/AppStateTests.swift`, append the following two tests inside the `AppStateTests` suite (after `saveAndLoadCredentials`):

```swift
@Test func signOutClearsPlatformCreditState() throws {
    let state = makeState()
    try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")
    state.platformCreditsIsStale = true
    state.cachedPlatformOrgId = "platform-org-1"

    state.signOut()

    #expect(state.platformCredits == nil)
    #expect(state.platformCreditsIsStale == false)
    #expect(state.cachedPlatformOrgId == nil)
}

@Test func handleSessionExpiredClearsPlatformCreditState() throws {
    let state = makeState()
    try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")
    state.platformCreditsIsStale = true
    state.cachedPlatformOrgId = "platform-org-1"

    state.handleSessionExpired()

    #expect(state.platformCredits == nil)
    #expect(state.platformCreditsIsStale == false)
    #expect(state.cachedPlatformOrgId == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter AppStateTests.signOutClearsPlatformCreditState`

Expected: build error — `value of type 'AppState' has no member 'platformCredits'`. This is the "red" state.

- [ ] **Step 3: Implement — add the three properties to `AppState`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add three properties under `// MARK: - Usage State` (after the existing `usage`, `organizationDetails`, `lastUpdated`, `isLoading`, `error` block around line 35):

```swift
// MARK: - Usage State
public var usage: UsageResponse?
public var organizationDetails: OrganizationDetails?
public var lastUpdated: Date?
public var isLoading = false
public var error: AppError?

// Platform (platform.claude.com) prepaid API credit balance. Independent of
// the currently-selected claude.ai org — `cachedPlatformOrgId` is the UUID of
// the *platform* org carrying the `api` capability, discovered once per session.
public var platformCredits: PlatformCredits?
public var platformCreditsIsStale: Bool = false
public var cachedPlatformOrgId: String?
```

- [ ] **Step 4: Clear the three new properties in `signOut()`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, modify `signOut()` (around line 109) — append the three new clears after the existing ones:

```swift
public func signOut() {
    try? keychain.delete(account: Self.credentialsAccount)
    sessionKey = nil
    orgId = nil
    usage = nil
    organizationDetails = nil
    organizations = []
    pendingSessionKey = nil
    pendingOrganizations = []
    pendingOrgPick = false
    platformCredits = nil
    platformCreditsIsStale = false
    cachedPlatformOrgId = nil
}
```

- [ ] **Step 5: Clear the three new properties in `handleSessionExpired()`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, modify `handleSessionExpired()` (around line 123) — append the three new clears:

```swift
func handleSessionExpired() {
    try? keychain.delete(account: Self.credentialsAccount)
    sessionKey = nil
    usage = nil
    organizationDetails = nil
    error = .sessionExpired
    platformCredits = nil
    platformCreditsIsStale = false
    cachedPlatformOrgId = nil
    // orgId and organizations: preserved
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter AppStateTests.signOutClearsPlatformCreditState && swift test --filter AppStateTests.handleSessionExpiredClearsPlatformCreditState`

Expected: both PASS.

- [ ] **Step 7: Run the full test suite**

Run: `swift test`

Expected: all tests pass (129 from Task 3 → expect 131 green).

- [ ] **Step 8: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(credits): track platform credit state on AppState"
```

---

## Task 5: Wire `refreshPlatformCredits` into `refreshUsage`

Add two pure state-transition helpers (testable without network) and one async method that performs the discover-then-fetch flow against `platform.claude.com`. Call the async method from a sibling `Task` inside `refreshUsage()` so a slow or failing platform call never delays the usage display.

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift` (add helpers + `refreshPlatformCredits(sessionKey:)`; modify `refreshUsage()` around line 238)
- Test: `Tests/AppStateTests.swift` (append three new tests for the pure helpers)

- [ ] **Step 1: Write the failing tests**

In `Tests/AppStateTests.swift`, append the following three tests (after the two added in Task 4):

```swift
@Test func applyPlatformCreditsSuccessSetsValueAndClearsStale() {
    let state = makeState()
    state.platformCreditsIsStale = true   // pre-existing stale state from a prior failed fetch

    state.applyPlatformCreditsSuccess(PlatformCredits(amountCents: 250, currency: "USD"))

    #expect(state.platformCredits?.amountCents == 250)
    #expect(state.platformCreditsIsStale == false)
}

@Test func markPlatformCreditsFetchFailedSetsStaleWhenValueExists() {
    let state = makeState()
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")

    state.markPlatformCreditsFetchFailed()

    #expect(state.platformCredits?.amountCents == 189)        // value preserved
    #expect(state.platformCreditsIsStale == true)
}

@Test func markPlatformCreditsFetchFailedNoOpWhenNoValue() {
    let state = makeState()
    // platformCredits is nil — there is no "stale" state to enter

    state.markPlatformCreditsFetchFailed()

    #expect(state.platformCredits == nil)
    #expect(state.platformCreditsIsStale == false)
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter AppStateTests.applyPlatformCreditsSuccessSetsValueAndClearsStale`

Expected: build error — `value of type 'AppState' has no member 'applyPlatformCreditsSuccess'`. This is the "red" state.

- [ ] **Step 3: Implement — add the two pure helpers**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add the following two methods inside the `AppState` class. Place them immediately before the `// MARK: - Polling` section (around line 279):

```swift
// MARK: - Platform Credits

/// Apply a successful platform credits fetch — value is updated, stale flag clears.
func applyPlatformCreditsSuccess(_ credits: PlatformCredits) {
    platformCredits = credits
    platformCreditsIsStale = false
}

/// Mark the most recent platform credits fetch as failed. Preserves the last
/// known value and sets the stale flag if (and only if) we have a value to
/// display — there is no "stale nothing" state.
func markPlatformCreditsFetchFailed() {
    if platformCredits != nil {
        platformCreditsIsStale = true
    }
}
```

- [ ] **Step 4: Run the helper tests to verify they pass**

Run: `swift test --filter AppStateTests.applyPlatformCreditsSuccessSetsValueAndClearsStale && swift test --filter AppStateTests.markPlatformCreditsFetchFailedSetsStaleWhenValueExists && swift test --filter AppStateTests.markPlatformCreditsFetchFailedNoOpWhenNoValue`

Expected: all three PASS.

- [ ] **Step 5: Add the `refreshPlatformCredits(sessionKey:)` async method**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add the async refresh method directly after the two helpers from Step 3:

```swift
/// Discover the API org (cached for the session) and fetch its prepaid
/// credit balance. On a `permission_error` 200 the cached UUID is invalidated
/// so the next call re-discovers. Network failures are silent: we keep the
/// last known balance and mark it stale.
func refreshPlatformCredits(sessionKey: String) async {
    // Discovery: if we have no cached UUID, list platform orgs and pick the
    // first one with the `api` capability.
    if cachedPlatformOrgId == nil {
        if let orgs = try? await ClaudeAPIClient.fetchPlatformOrganizations(sessionKey: sessionKey) {
            let apiOrgs = orgs.filter { $0.capabilities?.contains("api") == true }
            cachedPlatformOrgId = apiOrgs.first?.uuid
            // Multi-API-org: log and keep the first; revisit if a user reports it.
            if apiOrgs.count > 1 {
                NSLog("ClaudeBar: multiple platform API orgs found, using first (%@)", apiOrgs.first?.uuid ?? "?")
            }
        } else {
            // Discovery itself failed — nothing to do this cycle.
            markPlatformCreditsFetchFailed()
            return
        }
    }
    guard let orgId = cachedPlatformOrgId else { return }  // No API org for this account

    do {
        if let credits = try await ClaudeAPIClient.fetchPlatformCredits(
            sessionKey: sessionKey,
            platformOrgId: orgId
        ) {
            applyPlatformCreditsSuccess(credits)
        } else {
            // permission_error: cached UUID is stale or org lost `api`. Clear
            // cache so the next poll re-discovers; mark current value stale.
            cachedPlatformOrgId = nil
            markPlatformCreditsFetchFailed()
        }
    } catch {
        markPlatformCreditsFetchFailed()
    }
}
```

- [ ] **Step 6: Wire `refreshPlatformCredits` into `refreshUsage`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, modify `refreshUsage()` (currently at line 238). After the existing background org-list refresh `Task { ... }` block (around lines 254–261), append a sibling `Task` that fetches platform credits. The full updated method:

```swift
public func refreshUsage() async {
    guard let sessionKey, let orgId else { return }
    isLoading = true
    error = nil
    let client = ClaudeAPIClient(sessionKey: sessionKey, orgId: orgId)
    do {
        usage = try await client.fetchUsage()
        lastUpdated = Date()
        // Fetch org details once per session — tier is stable across polls.
        if organizationDetails == nil {
            organizationDetails = try? await client.fetchOrganizationDetails()
        }
        // Best-effort background refresh of the org list. Capture the
        // sessionKey at spawn; on completion, only apply if the user is
        // still signed in with that same key — avoids leaking the prior
        // account's orgs after sign-out or account switch.
        Task { [weak self, sessionKey] in
            if let fetched = try? await ClaudeAPIClient.fetchOrganizations(sessionKey: sessionKey) {
                await MainActor.run {
                    guard let self, self.sessionKey == sessionKey else { return }
                    self.applyRefreshedOrgList(fetched)
                }
            }
        }
        // Best-effort background refresh of the platform credit balance.
        // Same session-guard rule as above: drop the result if the user has
        // signed out or switched accounts in the meantime.
        Task { [weak self, sessionKey] in
            await MainActor.run {
                guard let self, self.sessionKey == sessionKey else { return }
                Task { @MainActor in
                    guard self.sessionKey == sessionKey else { return }
                    await self.refreshPlatformCredits(sessionKey: sessionKey)
                }
            }
        }
    } catch APIError.sessionExpired {
        handleSessionExpired()
    } catch APIError.rateLimited {
        error = .rateLimited
    } catch {
        self.error = .network(error.localizedDescription)
    }
    isLoading = false
}
```

- [ ] **Step 7: Run the full test suite**

Run: `swift test`

Expected: all tests pass (131 from Task 4 → expect 134 green). Network calls in the new refresh method are not invoked from any test (the tests never set `sessionKey`, so `refreshUsage()` returns at the guard).

- [ ] **Step 8: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(credits): fetch platform balance alongside usage poll"
```

---

## Task 6: Render `apiCreditsSection` in the popover + localization

Add the section view and the two localization strings. The section appears immediately after `extraUsageSection`, with a Divider above it. Layout matches the existing `overageBalance` row (label-on-left, semibold green value on right).

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift` (extend `body` around lines 9–21 and add `apiCreditsSection` after `extraUsageSection` around line 262)
- Modify: `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` (after `"section.apiCredits"` does not exist yet; add it next to other section keys)
- Modify: `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` (same)

No automated test — Task 7 covers this end-to-end manually.

- [ ] **Step 1: Add the English localization string**

In `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`, append the following line in the `usage.*` block (after `"usage.updatedAgo %@" = "Updated %@ ago";` around line 62):

```
"section.apiCredits" = "API Credits";
```

- [ ] **Step 2: Add the Russian localization string**

In `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`, append the following line in the same position (after `"usage.updatedAgo %@" = "Обновлено %@ назад";` around line 62):

```
"section.apiCredits" = "API кредиты";
```

- [ ] **Step 3: Add the `apiCreditsSection` view builder**

In `Sources/ClaudeBarUI/Views/UsageDetailView.swift`, add a new private function immediately after `extraUsageSection` (the closing `}` of `extraUsageSection` is around line 262, before the static `currencySymbol` helper):

```swift
private func apiCreditsSection(_ credits: PlatformCredits, isStale: Bool) -> some View {
    HStack {
        Text("section.apiCredits", bundle: .module)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer()
        Text(verbatim: credits.formatted())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 12)
    .opacity(isStale ? 0.5 : 1.0)
}
```

- [ ] **Step 4: Render the section in `body` after the extra-usage block**

In `Sources/ClaudeBarUI/Views/UsageDetailView.swift`, modify the `body` `if let usage = state.usage { ... }` block (around lines 9–21). After the existing `extraUsageSection(...)` call (which ends at the closing `}` of the `if let extra = ...` around line 21), insert the new section. The full updated block:

```swift
if let usage = state.usage {
    fiveHourSection(usage)
    Divider()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    sevenDaySection(usage)
    if let extra = usage.extraUsage, extra.isEnabled,
       let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0 {
        Divider()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        extraUsageSection(used: used, limit: limit, currency: extra.currency, overage: extra.overageBalance, overageCurrency: extra.overageBalanceCurrency)
    }
    if let credits = state.platformCredits {
        Divider()
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        apiCreditsSection(credits, isStale: state.platformCreditsIsStale)
    }
}
```

- [ ] **Step 5: Build and run the test suite**

Run: `swift test`

Expected: all 134 tests still pass (no new tests in this task; visual change covered by Task 7).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings
git commit -m "feat(credits): show API Credits row in popover after Extra Credits"
```

---

## Task 7: Manual UI smoke test

Per `CLAUDE.md`: UI changes must be verified end-to-end before reporting complete. The unit tests prove the data model and state machine are correct — this step proves the user actually sees the balance in the popover.

**Files:** none modified.

- [ ] **Step 1: Build and run the app**

Run: `./scripts/run.sh`

Expected: ClaudeBar appears in the menu bar (do **not** use `swift run` — the binary must be code-signed; see `CLAUDE.md`).

- [ ] **Step 2: Verify the popover shows the API Credits row**

Click the menu bar icon to open the popover. With a session that has at least one platform org carrying the `api` capability:

Expected:
- Existing usage rows render unchanged (5-Hour Window, 7-Day Windows, optional Extra Credits).
- A new **API Credits** row appears at the bottom of the data section, before the footer.
- The value is formatted in the user's locale — for `en_US` it should read `$1.89` (or whatever the live balance is).
- The value renders at full opacity.

- [ ] **Step 3: Verify the menu bar text is unchanged**

Look at the menu bar icon's label.

Expected: the label is unchanged from before the feature — exactly the 5h utilization percentage (e.g., `47%`). No `$` indicator.

- [ ] **Step 4: Verify org switching does not affect the balance**

If you have multiple claude.ai orgs in the switcher (e.g., a Pro org and a Team org alongside the API org), use the org switcher in the popover header to flip between them.

Expected:
- Usage rows update to reflect the newly-selected claude.ai org (different utilization values, possibly different tier pill).
- The **API Credits** row stays the same value across orgs — it is account-level, not per-org.

- [ ] **Step 5: Verify a no-API-org account hides the row**

If you have a second test account with only Pro/Team orgs and no API capability, sign in with it (Settings → Update session key) and reopen the popover.

Expected: no API Credits row appears. Usage rows render normally.

(Skip this step if no such account is available — the unit tests cover the `cachedPlatformOrgId == nil` path.)

- [ ] **Step 6: Quit the app**

Use the gear menu → Quit, or `⌘Q` while the popover is focused.

- [ ] **Step 7: No commit**

This task changes no files. Skip the commit step.

---

## Self-Review Notes

Re-read the spec (`docs/superpowers/specs/2026-05-09-platform-credit-balance-design.md`) and confirmed:

- **Spec coverage:**
  - Decision 1 (auth reuse, no new Keychain entry) → no setup-flow code changes needed; verified by inspection.
  - Decision 2 (org discovery, cache for session, re-discover on permission_error) → Task 5, `refreshPlatformCredits`.
  - Decision 3 (piggyback on existing `pollTimer`, parallel sibling Task) → Task 5, Step 6.
  - Decision 4 (multi-API-org: take first + log) → Task 5, Step 5 (`NSLog` warning).
  - Decision 5 (popover only, after Extra Credits) → Task 6, Steps 3–4.
  - Decision 6 (hidden when not applicable) → Task 6, Step 4 (`if let credits = state.platformCredits`).
  - Decision 7 (stale handling: keep value, dim) → Task 5 (state machine) + Task 6, Step 3 (`.opacity(isStale ? 0.5 : 1.0)`).
  - Decision 8 (currency formatting via `Decimal.FormatStyle.Currency`) → Task 1, Step 3.
  - Decision 9 (`amount` is cents) → Task 1, Step 3 (`/ 100.0`).
  - Acceptance criteria 1–6 → criterion 1 is Task 7 Step 2; criterion 2 is Task 7 Step 5; criterion 3 is Task 7 Step 3; criterion 4 is the stale state machine (Tasks 4–5) plus Task 6 Step 3 opacity; criterion 5 is Task 4 Step 4; criterion 6 is the cumulative `swift test` runs across Tasks 1–6.

- **No placeholders:** Every code step shows the exact code; every command step shows the exact command. No "TBD" / "implement later" / "appropriate handling".

- **Type/symbol consistency across tasks:** `PlatformCredits` (Task 1) — used in Tasks 2, 3, 4, 5, 6. Field names `amountCents`, `currency`, `amount`, `formatted(locale:)` consistent throughout. `cachedPlatformOrgId`, `platformCredits`, `platformCreditsIsStale` (Task 4) — used unchanged in Task 5 and Task 6. Method names `applyPlatformCreditsSuccess`, `markPlatformCreditsFetchFailed`, `refreshPlatformCredits(sessionKey:)` (Task 5) — referenced consistently. `fetchPlatformOrganizations(sessionKey:)`, `fetchPlatformCredits(sessionKey:platformOrgId:)` (Task 3) — match call sites in Task 5.

- **Order constraint:** Tasks 1 → 2 → 3 → 4 → 5 → 6 → 7. Task 1 introduces `PlatformCredits` (referenced by all later tasks). Task 2 adds parsers/builders (referenced by Task 3). Task 3 adds fetch methods (referenced by Task 5). Task 4 adds AppState properties (referenced by Tasks 5 and 6). Task 5 adds the refresh method (consumed by Task 6's UI which reads the resulting state). Task 6 surfaces the UI (verified by Task 7 manually). The order is strict.

- **Test count progression:** start 120 → +4 (T1) → +5 (T2) → +0 (T3) → +2 (T4) → +3 (T5) → +0 (T6) → +0 (T7) = 134 expected at the end.
