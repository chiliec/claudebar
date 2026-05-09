# Platform API Credit Balance v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the user's prepaid Anthropic API credit balance from `platform.claude.com`, using a separate platform-scoped `sessionKey` acquired via either an embedded WKWebView one-tap connect or manual paste. Strictly opt-in from Settings; onboarding and existing claude.ai usage display are unchanged.

**Architecture:** Five layers. (1) New `PlatformCredits` value type, a `PlatformAuthError` enum, and an extension on `ClaudeAPIClient` that talks to `platform.claude.com`. (2) New Keychain slot `"platform_credentials"` plus four properties on `AppState` (`platformSessionKey`, `platformCredits`, `platformCreditsIsStale`, `cachedPlatformOrgId`) and `connectPlatform(sessionKey:)` / `disconnectPlatform()` / `refreshPlatformCredits()` methods. The platform refresh runs as a sibling `Task` from `refreshUsage()` only when a platform key exists. (3) A new `PlatformAuthWebView` (`NSViewRepresentable` over `WKWebView` with isolated `WKWebsiteDataStore.nonPersistent()`) plus a `PlatformConnectSheet` modal hosting it. (4) A new `platformAPISection` in `SettingsView` rendering Disconnected / Connected / Stale states with `[Connect]` button, `[Disconnect]` button, and a manual-paste disclosure. (5) The existing popover gets the same `apiCreditsSection` row as v1, gated on `state.platformCredits != nil`. The menu bar text is unchanged. Critically: 401/403 from platform endpoints clears only the platform key — it does NOT trigger the global `handleSessionExpired()` flow that owns the claude.ai session.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Test` / `#expect`), Swift Package Manager, `URLSession`, `WebKit` (`WKWebView`, `WKHTTPCookieStore`, `WKNavigationDelegate`).

**Spec:** `docs/superpowers/specs/2026-05-09-platform-credit-balance-v2-design.md` (commit `1bd3ef5`)

---

## File Inventory

- **Modify:** `Sources/ClaudeBarUI/Models/UsageModel.swift` — append `PlatformCredits` struct after `OrganizationDetails`.
- **Modify:** `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift` — append `PlatformAuthError` enum + `extension ClaudeAPIClient` block with platform request builders, parsers, and fetch methods. Make `validateHTTPResponse` non-private.
- **Create:** `Sources/ClaudeBarUI/Services/PlatformAuthWebView.swift` — `NSViewRepresentable` wrapping `WKWebView` plus a static cookie-filter helper.
- **Create:** `Sources/ClaudeBarUI/Views/PlatformConnectSheet.swift` — modal sheet hosting the webview with 90s timeout.
- **Modify:** `Sources/ClaudeBarUI/Models/AppState.swift` — add four properties, `connectPlatform` / `disconnectPlatform` / `refreshPlatformCredits` methods, Keychain account constant, clear-on-signOut, wire into `refreshUsage`.
- **Modify:** `Sources/ClaudeBarUI/Views/SettingsView.swift` — add `platformAPISection` GroupBox below the existing `sessionGroup` with the three states.
- **Modify:** `Sources/ClaudeBarUI/Views/UsageDetailView.swift` — add `apiCreditsSection` after `extraUsageSection`.
- **Modify:** `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` — add `section.apiCredits` + `settings.platformAPI.*` keys.
- **Modify:** `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` — same keys (Russian translations).
- **Modify:** `Tests/UsageModelTests.swift` — `PlatformCredits` decode + format tests.
- **Modify:** `Tests/ClaudeAPIClientTests.swift` — platform request builders/parsers tests including 401/403 → `PlatformAuthError.sessionExpired` and `permission_error` 200 → `noApiOrg`.
- **Modify:** `Tests/AppStateTests.swift` — `connectPlatform` / `disconnectPlatform` state, platform-only key clear on platform expiry, sign-out clears all platform state.
- **Create:** `Tests/PlatformAuthWebViewTests.swift` — pure cookie-filter logic tests (no `WKWebView` instantiation).

---

## Task 1: Add `PlatformCredits` model

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/UsageModel.swift` (append after `OrganizationDetails`, before `SubscriptionTier`, around line 135)
- Test: `Tests/UsageModelTests.swift` (append after the last existing test, around line 230)

- [ ] **Step 1: Write the failing tests**

Append in `Tests/UsageModelTests.swift`:

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
    let json = #"{ "amount": 0, "currency": "USD" }"#.data(using: .utf8)!
    let credits = try JSONDecoder().decode(PlatformCredits.self, from: json)
    #expect(credits.amountCents == 0)
    #expect(credits.amount == 0.0)
}

@Test func platformCreditsFormattedUSEnglish() {
    let credits = PlatformCredits(amountCents: 189, currency: "USD")
    let formatted = credits.formatted(locale: Locale(identifier: "en_US"))
    #expect(formatted.contains("1.89"))
    #expect(formatted.contains("$"))
}

@Test func platformCreditsFormattedLargeAmount() {
    let credits = PlatformCredits(amountCents: 1_234_567, currency: "USD")
    let formatted = credits.formatted(locale: Locale(identifier: "en_US"))
    #expect(formatted.contains("12,345.67"))
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter UsageModelTests.decodePlatformCreditsResponse`

Expected: build error — `cannot find 'PlatformCredits' in scope`.

- [ ] **Step 3: Implement — append the struct**

In `Sources/ClaudeBarUI/Models/UsageModel.swift`, append after the closing `}` of `OrganizationDetails` (around line 135):

```swift
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

    public var amount: Double { Double(amountCents) / 100.0 }

    public func formatted(locale: Locale = .current) -> String {
        let decimal = Decimal(amountCents) / 100
        return decimal.formatted(.currency(code: currency).locale(locale))
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter UsageModelTests.decodePlatformCreditsResponse && swift test --filter UsageModelTests.decodePlatformCreditsZeroBalance && swift test --filter UsageModelTests.platformCreditsFormattedUSEnglish && swift test --filter UsageModelTests.platformCreditsFormattedLargeAmount`

Expected: all four PASS.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`

Expected: green (120 → 124).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Models/UsageModel.swift Tests/UsageModelTests.swift
git commit -m "feat(credits): add PlatformCredits model"
```

---

## Task 2: Add `PlatformAuthError` and platform request builders/parsers

Pure functions: two request builders (org list, credits) and two parsers. Network-free. Adds `PlatformAuthError` so 401/403 from platform endpoints can be distinguished from claude.ai's `APIError.sessionExpired` — critical for keeping platform expiry from triggering the global session-expired flow.

**Files:**
- Modify: `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift` (drop `private` on `validateHTTPResponse`; append `PlatformAuthError` and `extension ClaudeAPIClient` block at bottom)
- Test: `Tests/ClaudeAPIClientTests.swift` (append after `parseOrganizationsResponse`, around line 51)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeAPIClientTests.swift`:

```swift
@Test func buildPlatformOrganizationsRequest() throws {
    let request = try ClaudeAPIClient.buildPlatformOrganizationsRequest(platformSessionKey: "sk-test")
    #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations")
    #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
    #expect(request.value(forHTTPHeaderField: "anthropic-client-platform") == "web_console")
    #expect(request.httpMethod == "GET")
}

@Test func buildPlatformCreditsRequest() throws {
    let request = try ClaudeAPIClient.buildPlatformCreditsRequest(
        platformSessionKey: "sk-test",
        platformOrgId: "8bc28b46-d6dd-4982-a38a-66a11be1c437"
    )
    #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations/8bc28b46-d6dd-4982-a38a-66a11be1c437/prepaid/credits")
    #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
    #expect(request.value(forHTTPHeaderField: "anthropic-client-platform") == "web_console")
    #expect(request.value(forHTTPHeaderField: "Referer") == "https://platform.claude.com/settings/billing")
}

@Test func parsePlatformOrganizationsIgnoresExtraFields() throws {
    let json = """
    [
      {
        "id": 136002694,
        "uuid": "4f4dee87-d910-4390-ae54-b64ad23b9243",
        "name": "Personal",
        "settings": { "claude_console_privacy": "default_private" },
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

Expected: build error — `type 'ClaudeAPIClient' has no member 'buildPlatformOrganizationsRequest'`.

- [ ] **Step 3: Make `validateHTTPResponse` non-private**

In `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`, change line 103 from:

```swift
private static func validateHTTPResponse(_ response: URLResponse) throws {
```

to:

```swift
static func validateHTTPResponse(_ response: URLResponse) throws {
```

(Drop `private`.)

- [ ] **Step 4: Add `PlatformAuthError` and the platform extension**

In `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`, append at the bottom of the file (after the existing `ISO8601DateFormatter` extension around line 146):

```swift
// MARK: - platform.claude.com (prepaid API credits)

public enum PlatformAuthError: Error, Equatable {
    /// 401/403 from platform.claude.com — clear ONLY the platform key.
    /// Distinct from APIError.sessionExpired which owns the claude.ai key.
    case sessionExpired
    /// Listing returned 200 but no org has the `api` capability.
    case noApiOrg
}

extension ClaudeAPIClient {
    private static let platformBaseURL = "https://platform.claude.com"

    private static func applyPlatformHeaders(_ request: inout URLRequest, platformSessionKey: String) {
        request.setValue("sessionKey=\(platformSessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("web_console", forHTTPHeaderField: "anthropic-client-platform")
        request.setValue("https://platform.claude.com/settings/billing", forHTTPHeaderField: "Referer")
    }

    public static func buildPlatformOrganizationsRequest(platformSessionKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(platformBaseURL)/api/organizations") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyPlatformHeaders(&request, platformSessionKey: platformSessionKey)
        return request
    }

    public static func buildPlatformCreditsRequest(platformSessionKey: String, platformOrgId: String) throws -> URLRequest {
        guard let url = URL(string: "\(platformBaseURL)/api/organizations/\(platformOrgId)/prepaid/credits") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyPlatformHeaders(&request, platformSessionKey: platformSessionKey)
        return request
    }

    public static func parsePlatformOrganizationsResponse(data: Data) throws -> [Organization] {
        return try JSONDecoder().decode([Organization].self, from: data)
    }

    /// Parse the prepaid credits response. Returns `nil` for the
    /// `permission_error` 200 body (session valid, org has no credits).
    public static func parsePlatformCreditsResponse(data: Data) throws -> PlatformCredits? {
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

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter ClaudeAPIClientTests`

Expected: all pass (the new five plus the existing four).

- [ ] **Step 6: Run the full test suite**

Run: `swift test`

Expected: green (124 → 129).

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift Tests/ClaudeAPIClientTests.swift
git commit -m "feat(credits): platform request builders, parsers, and PlatformAuthError"
```

---

## Task 3: Add `fetchPlatformOrganizations` and `fetchPlatformCredits` network methods

Map HTTP 401/403 to `PlatformAuthError.sessionExpired` (NOT to `APIError.sessionExpired` which would trigger the global expiry flow). Following the existing convention these are not unit-tested in isolation — the parsers and request builders cover the logic.

**Files:**
- Modify: `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift` (extend the platform extension)

- [ ] **Step 1: Add a platform-only validator and the two fetch methods**

In `Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift`, append inside the `extension ClaudeAPIClient` block from Task 2 (after `parsePlatformCreditsResponse`):

```swift
/// Like `validateHTTPResponse` but maps 401/403 to `PlatformAuthError.sessionExpired`
/// instead of `APIError.sessionExpired`. Critical: a platform-side 401/403 must NOT
/// drag the user through the global handleSessionExpired() flow that wipes the
/// claude.ai key and ejects to SetupView.
static func validatePlatformHTTPResponse(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else {
        throw APIError.invalidResponse
    }
    switch http.statusCode {
    case 200: return
    case 401, 403: throw PlatformAuthError.sessionExpired
    case 429: throw APIError.rateLimited
    default: throw APIError.httpError(http.statusCode)
    }
}

public static func fetchPlatformOrganizations(platformSessionKey: String) async throws -> [Organization] {
    let request = try buildPlatformOrganizationsRequest(platformSessionKey: platformSessionKey)
    let (data, response) = try await URLSession.shared.data(for: request)
    try validatePlatformHTTPResponse(response)
    return try parsePlatformOrganizationsResponse(data: data)
}

/// Returns `nil` when the org has no prepaid credits (permission_error 200).
/// Throws `PlatformAuthError.sessionExpired` on 401/403.
public static func fetchPlatformCredits(platformSessionKey: String, platformOrgId: String) async throws -> PlatformCredits? {
    let request = try buildPlatformCreditsRequest(platformSessionKey: platformSessionKey, platformOrgId: platformOrgId)
    let (data, response) = try await URLSession.shared.data(for: request)
    try validatePlatformHTTPResponse(response)
    return try parsePlatformCreditsResponse(data: data)
}
```

- [ ] **Step 2: Build to confirm compilation**

Run: `swift build`

Expected: build succeeds with no warnings.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`

Expected: green (count unchanged at 129).

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeBarUI/Services/ClaudeAPIClient.swift
git commit -m "feat(credits): fetchPlatformOrganizations and fetchPlatformCredits"
```

---

## Task 4: Add platform state + Keychain slot to `AppState` (no fetch yet)

Properties and lifecycle only. The async `connectPlatform` / `refreshPlatformCredits` methods land in Task 5.

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift` (add account constant, four properties, modify `loadCredentials`, `signOut`)
- Test: `Tests/AppStateTests.swift` (append three tests)

- [ ] **Step 1: Write the failing tests**

Append in `Tests/AppStateTests.swift`:

```swift
@Test func signOutClearsAllPlatformState() throws {
    let state = makeState()
    try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
    state.platformSessionKey = "sk-platform"
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")
    state.platformCreditsIsStale = true
    state.cachedPlatformOrgId = "platform-org-1"

    state.signOut()

    #expect(state.platformSessionKey == nil)
    #expect(state.platformCredits == nil)
    #expect(state.platformCreditsIsStale == false)
    #expect(state.cachedPlatformOrgId == nil)
}

@Test func handleSessionExpiredDoesNotTouchPlatformState() throws {
    // Critical regression guard: claude.ai expiry MUST NOT clear the platform
    // key. The two sessions are independent.
    let state = makeState()
    try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
    state.platformSessionKey = "sk-platform"
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")
    state.cachedPlatformOrgId = "platform-org-1"

    state.handleSessionExpired()

    #expect(state.platformSessionKey == "sk-platform")
    #expect(state.platformCredits?.amountCents == 189)
    #expect(state.cachedPlatformOrgId == "platform-org-1")
}

@Test func loadCredentialsRestoresPlatformKeyFromKeychain() throws {
    let state = makeState()
    // Pre-seed keychain via a fresh service instance using the same test name
    let kc = KeychainService(serviceName: "com.claudebar.test")
    try kc.save(account: "platform_credentials", value: "sk-platform-restored")

    state.loadCredentials()

    #expect(state.platformSessionKey == "sk-platform-restored")
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter AppStateTests.signOutClearsAllPlatformState`

Expected: build error — `value of type 'AppState' has no member 'platformSessionKey'`.

- [ ] **Step 3: Add the Keychain account constant and four properties**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add the constant beside `credentialsAccount` (around line 91):

```swift
private static let credentialsAccount = "credentials"
private static let credentialsSeparator: Character = "\0"
private static let platformCredentialsAccount = "platform_credentials"
```

Add four properties under `// MARK: - Usage State` (after the existing `error` declaration around line 35):

```swift
// Platform (platform.claude.com) prepaid API credit balance — independent of
// the claude.ai session. `platformSessionKey` is the host-only sessionKey
// captured from platform.claude.com (NOT the claude.ai key).
public var platformSessionKey: String?
public var platformCredits: PlatformCredits?
public var platformCreditsIsStale: Bool = false
public var cachedPlatformOrgId: String?
```

- [ ] **Step 4: Restore platform key in `loadCredentials`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, modify `loadCredentials()` (around line 94) — append the platform restore at the end:

```swift
public func loadCredentials() {
    guard let stored = try? keychain.retrieve(account: Self.credentialsAccount) else {
        // Even with no claude.ai credentials, a platform key may exist independently.
        platformSessionKey = try? keychain.retrieve(account: Self.platformCredentialsAccount)
        return
    }
    let parts = stored.split(separator: Self.credentialsSeparator, maxSplits: 1)
    guard parts.count == 2 else { return }
    sessionKey = String(parts[0])
    orgId = String(parts[1])
    platformSessionKey = try? keychain.retrieve(account: Self.platformCredentialsAccount)
}
```

- [ ] **Step 5: Clear platform state in `signOut()`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, modify `signOut()` (around line 109) — append the platform clears AND delete the platform Keychain entry. Sign-out is total; the platform credential goes too:

```swift
public func signOut() {
    try? keychain.delete(account: Self.credentialsAccount)
    try? keychain.delete(account: Self.platformCredentialsAccount)
    sessionKey = nil
    orgId = nil
    usage = nil
    organizationDetails = nil
    organizations = []
    pendingSessionKey = nil
    pendingOrganizations = []
    pendingOrgPick = false
    platformSessionKey = nil
    platformCredits = nil
    platformCreditsIsStale = false
    cachedPlatformOrgId = nil
}
```

- [ ] **Step 6: Confirm `handleSessionExpired()` is unchanged**

In `Sources/ClaudeBarUI/Models/AppState.swift`, verify `handleSessionExpired()` (around line 123) does NOT touch any `platform*` field. The test in Step 1 (`handleSessionExpiredDoesNotTouchPlatformState`) is the regression guard. Do not edit this method in this task.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter AppStateTests.signOutClearsAllPlatformState && swift test --filter AppStateTests.handleSessionExpiredDoesNotTouchPlatformState && swift test --filter AppStateTests.loadCredentialsRestoresPlatformKeyFromKeychain`

Expected: all three PASS.

- [ ] **Step 8: Run the full test suite**

Run: `swift test`

Expected: green (129 → 132).

- [ ] **Step 9: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(credits): platform state and Keychain slot on AppState"
```

---

## Task 5: `connectPlatform`, `disconnectPlatform`, `refreshPlatformCredits`, and pollTimer wiring

The connect/disconnect entry points the UI calls. Pure state-transition helpers (`applyPlatformCreditsSuccess`, `markPlatformCreditsFetchFailed`, `applyPlatformSessionExpired`) plus the async refresh flow. Wire into `refreshUsage()` so the platform fetch piggybacks on the existing poll cycle when (and only when) `platformSessionKey != nil`.

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift` (add helpers, async methods, wire `refreshUsage`)
- Test: `Tests/AppStateTests.swift` (append five tests)

- [ ] **Step 1: Write the failing tests**

Append in `Tests/AppStateTests.swift`:

```swift
@Test func applyPlatformCreditsSuccessSetsValueAndClearsStale() {
    let state = makeState()
    state.platformCreditsIsStale = true

    state.applyPlatformCreditsSuccess(PlatformCredits(amountCents: 250, currency: "USD"))

    #expect(state.platformCredits?.amountCents == 250)
    #expect(state.platformCreditsIsStale == false)
}

@Test func markPlatformCreditsFetchFailedSetsStaleWhenValueExists() {
    let state = makeState()
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")

    state.markPlatformCreditsFetchFailed()

    #expect(state.platformCredits?.amountCents == 189)
    #expect(state.platformCreditsIsStale == true)
}

@Test func markPlatformCreditsFetchFailedNoOpWhenNoValue() {
    let state = makeState()

    state.markPlatformCreditsFetchFailed()

    #expect(state.platformCredits == nil)
    #expect(state.platformCreditsIsStale == false)
}

@Test func applyPlatformSessionExpiredClearsPlatformKeyAndCacheButPreservesUsage() throws {
    let state = makeState()
    try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
    state.platformSessionKey = "sk-platform"
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")
    state.cachedPlatformOrgId = "platform-org-1"

    state.applyPlatformSessionExpired()

    // Platform side cleared
    #expect(state.platformSessionKey == nil)
    #expect(state.platformCredits == nil)
    #expect(state.platformCreditsIsStale == false)
    #expect(state.cachedPlatformOrgId == nil)
    // claude.ai side preserved
    #expect(state.sessionKey == "sk")
    #expect(state.orgId == "org-1")
    #expect(state.error == nil)
}

@Test func disconnectPlatformDeletesKeychainEntryAndClearsState() throws {
    let state = makeState()
    let kc = KeychainService(serviceName: "com.claudebar.test")
    try kc.save(account: "platform_credentials", value: "sk-platform")
    state.platformSessionKey = "sk-platform"
    state.platformCredits = PlatformCredits(amountCents: 189, currency: "USD")
    state.cachedPlatformOrgId = "platform-org-1"

    state.disconnectPlatform()

    #expect(state.platformSessionKey == nil)
    #expect(state.platformCredits == nil)
    #expect(state.cachedPlatformOrgId == nil)
    #expect((try? kc.retrieve(account: "platform_credentials")) == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter AppStateTests.applyPlatformCreditsSuccessSetsValueAndClearsStale`

Expected: build error — `value of type 'AppState' has no member 'applyPlatformCreditsSuccess'`.

- [ ] **Step 3: Add the three pure helpers**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add a new section immediately before the `// MARK: - Polling` section (around line 279):

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

/// 401/403 from a platform endpoint — clear ONLY the platform side. The
/// claude.ai sessionKey, orgId, usage display, and global error state are
/// untouched. Settings shows "Disconnected · session expired" via the absence
/// of `platformSessionKey`.
func applyPlatformSessionExpired() {
    try? keychain.delete(account: Self.platformCredentialsAccount)
    platformSessionKey = nil
    platformCredits = nil
    platformCreditsIsStale = false
    cachedPlatformOrgId = nil
}
```

- [ ] **Step 4: Add `connectPlatform`, `disconnectPlatform`, and `refreshPlatformCredits`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, append after `applyPlatformSessionExpired` (still inside the `// MARK: - Platform Credits` section):

```swift
/// Save a platform-scoped sessionKey to Keychain and trigger an immediate
/// balance refresh. Called by both the WKWebView capture path and the manual
/// paste path — they share the same downstream pipeline.
public func connectPlatform(sessionKey: String) async {
    do {
        try keychain.save(account: Self.platformCredentialsAccount, value: sessionKey)
    } catch {
        self.error = .network(error.localizedDescription)
        return
    }
    platformSessionKey = sessionKey
    cachedPlatformOrgId = nil       // force re-discovery for the new account
    await refreshPlatformCredits()
}

/// User-initiated disconnect: drop the Keychain entry, clear all platform state.
public func disconnectPlatform() {
    try? keychain.delete(account: Self.platformCredentialsAccount)
    platformSessionKey = nil
    platformCredits = nil
    platformCreditsIsStale = false
    cachedPlatformOrgId = nil
}

/// Discover the API org (cached for the session) and fetch its prepaid credit
/// balance. No-op when `platformSessionKey == nil` — the caller does not need
/// to gate. Network failures are silent: keep the last known value, mark stale.
/// 401/403 specifically clears the platform key (decision #8 in the v2 spec).
func refreshPlatformCredits() async {
    guard let key = platformSessionKey else { return }

    if cachedPlatformOrgId == nil {
        do {
            let orgs = try await ClaudeAPIClient.fetchPlatformOrganizations(platformSessionKey: key)
            let apiOrgs = orgs.filter { $0.capabilities?.contains("api") == true }
            cachedPlatformOrgId = apiOrgs.first?.uuid
            if apiOrgs.count > 1 {
                NSLog("ClaudeBar: multiple platform API orgs found, using first (%@)", apiOrgs.first?.uuid ?? "?")
            }
        } catch is PlatformAuthError {
            applyPlatformSessionExpired()
            return
        } catch {
            markPlatformCreditsFetchFailed()
            return
        }
    }
    guard let orgId = cachedPlatformOrgId else { return }   // No API org for this account

    do {
        if let credits = try await ClaudeAPIClient.fetchPlatformCredits(
            platformSessionKey: key, platformOrgId: orgId
        ) {
            applyPlatformCreditsSuccess(credits)
        } else {
            // permission_error 200 — cached UUID stale or org lost `api`.
            cachedPlatformOrgId = nil
            markPlatformCreditsFetchFailed()
        }
    } catch is PlatformAuthError {
        applyPlatformSessionExpired()
    } catch {
        markPlatformCreditsFetchFailed()
    }
}
```

- [ ] **Step 5: Wire `refreshPlatformCredits` into `refreshUsage`**

In `Sources/ClaudeBarUI/Models/AppState.swift`, modify `refreshUsage()` (currently at line 238). After the existing background org-list refresh `Task { ... }` block (around lines 254–261), append a sibling `Task` that fetches platform credits. Final method:

```swift
public func refreshUsage() async {
    guard let sessionKey, let orgId else { return }
    isLoading = true
    error = nil
    let client = ClaudeAPIClient(sessionKey: sessionKey, orgId: orgId)
    do {
        usage = try await client.fetchUsage()
        lastUpdated = Date()
        if organizationDetails == nil {
            organizationDetails = try? await client.fetchOrganizationDetails()
        }
        Task { [weak self, sessionKey] in
            if let fetched = try? await ClaudeAPIClient.fetchOrganizations(sessionKey: sessionKey) {
                await MainActor.run {
                    guard let self, self.sessionKey == sessionKey else { return }
                    self.applyRefreshedOrgList(fetched)
                }
            }
        }
        // Platform credits — no-ops when no platform key is connected.
        Task { @MainActor [weak self] in
            await self?.refreshPlatformCredits()
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

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter AppStateTests`

Expected: all `AppStateTests` pass (the five new tests plus the existing ones).

- [ ] **Step 7: Run the full test suite**

Run: `swift test`

Expected: green (132 → 137).

- [ ] **Step 8: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(credits): connect/disconnect/refresh platform balance flow"
```

---

## Task 6: `PlatformAuthWebView` — `WKWebView` capture with isolated cookie store

`NSViewRepresentable` wrapping `WKWebView`. Uses `WKWebsiteDataStore.nonPersistent()` so cookies don't leak into Safari and the user always sees a fresh login. The cookie-filter predicate is exposed as a `static func` so tests can exercise it without instantiating a webview (which is impractical in the SPM test target).

**Files:**
- Create: `Sources/ClaudeBarUI/Services/PlatformAuthWebView.swift`
- Create: `Tests/PlatformAuthWebViewTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/PlatformAuthWebViewTests.swift`:

```swift
import Testing
import WebKit
@testable import ClaudeBarUI

@MainActor
@Suite
struct PlatformAuthWebViewTests {
    @Test func extractsSessionKeyForPlatformDomain() {
        let target = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "sk-ant-sid02-platform-value",
            .domain: "platform.claude.com",
            .path: "/",
        ])!
        let other = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "sk-ant-sid02-claudeai-value",
            .domain: ".claude.com",
            .path: "/",
        ])!

        let result = PlatformAuthWebView.extractPlatformSessionKey(from: [other, target])

        #expect(result == "sk-ant-sid02-platform-value")
    }

    @Test func ignoresCookiesFromWrongDomain() {
        let cookie = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "sk-claudeai",
            .domain: ".claude.com",
            .path: "/",
        ])!

        #expect(PlatformAuthWebView.extractPlatformSessionKey(from: [cookie]) == nil)
    }

    @Test func ignoresWrongName() {
        let cookie = HTTPCookie(properties: [
            .name: "csrf",
            .value: "whatever",
            .domain: "platform.claude.com",
            .path: "/",
        ])!

        #expect(PlatformAuthWebView.extractPlatformSessionKey(from: [cookie]) == nil)
    }

    @Test func returnsNilForEmptyCookies() {
        #expect(PlatformAuthWebView.extractPlatformSessionKey(from: []) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail (compile error)**

Run: `swift test --filter PlatformAuthWebViewTests`

Expected: build error — `cannot find 'PlatformAuthWebView' in scope`.

- [ ] **Step 3: Implement — create `PlatformAuthWebView.swift`**

Create `Sources/ClaudeBarUI/Services/PlatformAuthWebView.swift`:

```swift
import SwiftUI
import WebKit

@MainActor
public struct PlatformAuthWebView: NSViewRepresentable {
    public let onCapture: (String) -> Void
    public let onCancel: () -> Void

    public init(onCapture: @escaping (String) -> Void, onCancel: @escaping (String) -> Void = { _ in }) {
        self.onCapture = onCapture
        self.onCancel = { onCancel("cancel") }
    }

    public init(onCapture: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Isolated, non-persistent data store: fresh login every time, no Safari pollution.
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        if let url = URL(string: "https://platform.claude.com/login") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Pure cookie-filter predicate. Exposed for unit testing — `WKWebView`
    /// itself is impractical to instantiate from the test target.
    public static func extractPlatformSessionKey(from cookies: [HTTPCookie]) -> String? {
        cookies.first { cookie in
            cookie.name == "sessionKey" && cookie.domain == "platform.claude.com"
        }?.value
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PlatformAuthWebView
        private var captured = false

        init(parent: PlatformAuthWebView) {
            self.parent = parent
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !captured else { return }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                guard let self, !self.captured else { return }
                guard let value = PlatformAuthWebView.extractPlatformSessionKey(from: cookies) else { return }
                self.captured = true
                Task { @MainActor in self.parent.onCapture(value) }
            }
        }
    }
}
```

(Note: the duplicate `init` was a typo — keep only the second `init`. Replace the file's `init` block with just:

```swift
public init(onCapture: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
    self.onCapture = onCapture
    self.onCancel = onCancel
}
```

Remove the first `init`.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PlatformAuthWebViewTests`

Expected: all four PASS.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`

Expected: green (137 → 141).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Services/PlatformAuthWebView.swift Tests/PlatformAuthWebViewTests.swift
git commit -m "feat(credits): WKWebView wrapper for platform.claude.com auth capture"
```

---

## Task 7: `PlatformConnectSheet` — modal sheet with 90s timeout

Hosts the `PlatformAuthWebView` in a SwiftUI sheet. Owns a `Task` that auto-dismisses after 90 seconds. Calls `state.connectPlatform(sessionKey:)` on capture.

**Files:**
- Create: `Sources/ClaudeBarUI/Views/PlatformConnectSheet.swift`

No automated test — exercised by the manual smoke (Task 11).

- [ ] **Step 1: Implement — create `PlatformConnectSheet.swift`**

Create `Sources/ClaudeBarUI/Views/PlatformConnectSheet.swift`:

```swift
import SwiftUI

public struct PlatformConnectSheet: View {
    @Bindable public var state: AppState
    @Binding public var isPresented: Bool
    @Binding public var timedOut: Bool

    @State private var timeoutTask: Task<Void, Never>?

    public init(state: AppState, isPresented: Binding<Bool>, timedOut: Binding<Bool>) {
        self.state = state
        self._isPresented = isPresented
        self._timedOut = timedOut
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("settings.platformAPI.connectSheet.title", bundle: .module)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("action.cancel", bundle: .module)
                }
                .modifier(BorderedButtonModifier())
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            PlatformAuthWebView(
                onCapture: { capturedKey in
                    Task { @MainActor in
                        await state.connectPlatform(sessionKey: capturedKey)
                        dismiss()
                    }
                },
                onCancel: { dismiss() }
            )
        }
        .frame(width: 640, height: 720)
        .onAppear {
            timedOut = false
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(90))
                guard !Task.isCancelled, isPresented else { return }
                timedOut = true
                isPresented = false
            }
        }
        .onDisappear {
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }

    private func dismiss() {
        timeoutTask?.cancel()
        timeoutTask = nil
        isPresented = false
    }
}
```

- [ ] **Step 2: Build to confirm compilation**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 3: Run the full test suite**

Run: `swift test`

Expected: green (count unchanged at 141).

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeBarUI/Views/PlatformConnectSheet.swift
git commit -m "feat(credits): platform connect modal sheet with 90s timeout"
```

---

## Task 8: `platformAPISection` in `SettingsView` (three states + manual paste)

Adds the GroupBox and renders Disconnected / Connected / Stale states with the `[Connect]` button (opens the sheet from Task 7), `[Disconnect]` button, and a manual-paste disclosure that writes through `state.connectPlatform(sessionKey:)`.

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/SettingsView.swift` (add GroupBox between `sessionGroup` and the General GroupBox; add `@State` for sheet + paste field)

No automated test — exercised by the manual smoke (Task 11).

- [ ] **Step 1: Add `@State` for sheet, timeout, paste field**

In `Sources/ClaudeBarUI/Views/SettingsView.swift`, add three `@State` declarations alongside the existing `keyDraft` (around line 7):

```swift
@State private var keyDraft: String = ""
@State private var inlineKeyError: String?
@State private var showingPlatformConnect = false
@State private var platformSheetTimedOut = false
@State private var platformPasteDraft: String = ""
@State private var platformPasteError: String?
@State private var showingPlatformPaste = false
```

- [ ] **Step 2: Render the new GroupBox**

In `Sources/ClaudeBarUI/Views/SettingsView.swift`, modify `body` (around line 12). Insert the new GroupBox between `sessionGroup` and the General GroupBox:

```swift
public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
        HStack { /* title + Done — unchanged */ }

        sessionGroup
        platformAPISection

        // Launch at login GroupBox — unchanged

        Spacer()
        Divider()
        QuitButton()
    }
    .padding(16)
    .frame(width: 360, height: 460)   // was 320 × 360 — grow for the new section
    .sheet(isPresented: $showingPlatformConnect) {
        PlatformConnectSheet(
            state: state,
            isPresented: $showingPlatformConnect,
            timedOut: $platformSheetTimedOut
        )
    }
}
```

- [ ] **Step 3: Add the `platformAPISection` view builder**

In `Sources/ClaudeBarUI/Views/SettingsView.swift`, add `platformAPISection` after the `sessionGroup` definition (before `connectionStatusLine` around line 81):

```swift
@ViewBuilder
private var platformAPISection: some View {
    GroupBox {
        VStack(alignment: .leading, spacing: 10) {
            platformStatusRow

            DisclosureGroup(isExpanded: $showingPlatformPaste) {
                platformPasteField
            } label: {
                Text(state.platformSessionKey == nil
                     ? "settings.platformAPI.pasteManually"
                     : "settings.platformAPI.replaceKey",
                     bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if platformSheetTimedOut {
                Text("settings.platformAPI.connectSheet.timeout", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    } label: {
        Text("settings.platformAPI", bundle: .module)
    }
}

@ViewBuilder
private var platformStatusRow: some View {
    HStack {
        Circle()
            .fill(state.platformSessionKey != nil ? .green : .secondary)
            .frame(width: 8, height: 8)
        if let credits = state.platformCredits, state.platformSessionKey != nil {
            Text("settings.platformAPI.connected", bundle: .module)
                .font(.subheadline)
            Text(verbatim: "· \(credits.formatted())")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if state.platformSessionKey != nil {
            Text("settings.platformAPI.connected", bundle: .module)
                .font(.subheadline)
        } else {
            Text("settings.platformAPI.notConnected", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Spacer()
        if state.platformSessionKey == nil {
            Button {
                platformSheetTimedOut = false
                showingPlatformConnect = true
            } label: {
                Text("settings.platformAPI.connect", bundle: .module)
            }
            .modifier(BorderedButtonModifier())
            .controlSize(.small)
        } else {
            Button {
                state.disconnectPlatform()
                platformPasteDraft = ""
                platformPasteError = nil
            } label: {
                Text("settings.platformAPI.disconnect", bundle: .module)
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

@ViewBuilder
private var platformPasteField: some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            SecureField("", text: $platformPasteDraft, prompt: Text("setup.sessionKeyPlaceholder", bundle: .module))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            Button {
                let trimmed = platformPasteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                guard trimmed.hasPrefix("sk-ant-") else {
                    platformPasteError = String(localized: "update.badKey", bundle: .module)
                    return
                }
                platformPasteError = nil
                Task {
                    await state.connectPlatform(sessionKey: trimmed)
                    platformPasteDraft = ""
                    showingPlatformPaste = false
                }
            } label: {
                Text("action.update", bundle: .module)
            }
            .modifier(BorderedButtonModifier())
            .controlSize(.small)
            .disabled(platformPasteDraft.isEmpty)
        }
        if let platformPasteError {
            Text(platformPasteError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 4: Build to confirm compilation**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`

Expected: green (count unchanged at 141; this task adds no automated tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Views/SettingsView.swift
git commit -m "feat(credits): Settings section for Platform API connect/paste/disconnect"
```

---

## Task 9: `apiCreditsSection` in `UsageDetailView`

The popover row, mirroring v1. Gated on `state.platformCredits != nil`, dimmed when `platformCreditsIsStale == true`.

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift`

- [ ] **Step 1: Add the view builder**

In `Sources/ClaudeBarUI/Views/UsageDetailView.swift`, add a new private function immediately after the existing `extraUsageSection` (around line 262):

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

- [ ] **Step 2: Render the section in `body`**

In `Sources/ClaudeBarUI/Views/UsageDetailView.swift`, modify `body` (around lines 9–21). Insert the new section after the existing `extraUsageSection(...)` block:

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

- [ ] **Step 3: Build to confirm compilation**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`

Expected: green (count unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift
git commit -m "feat(credits): show API Credits row in popover after Extra Credits"
```

---

## Task 10: Localization strings

The view-layer Tasks 7–9 reference these keys; they currently render as the literal key string. Add them in both locales now (the keys are stable and the strings small).

**Files:**
- Modify: `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Append the English strings**

In `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`, append (alphabetical order: section.* keys go in the middle alongside existing settings.* / setup.* keys; `section.apiCredits` near other `usage.*` block, and `settings.platformAPI.*` after the existing `settings.*` block — exact placement is cosmetic, the file uses no headers):

```
"section.apiCredits" = "API Credits";
"settings.platformAPI" = "Platform API";
"settings.platformAPI.notConnected" = "Not connected · API balance hidden";
"settings.platformAPI.connected" = "Connected";
"settings.platformAPI.expired" = "Disconnected · session expired";
"settings.platformAPI.connect" = "Connect";
"settings.platformAPI.disconnect" = "Disconnect";
"settings.platformAPI.pasteManually" = "Paste cookie manually";
"settings.platformAPI.replaceKey" = "Replace key…";
"settings.platformAPI.connectSheet.title" = "Connect to platform.claude.com";
"settings.platformAPI.connectSheet.timeout" = "Connection timed out";
```

- [ ] **Step 2: Append the Russian strings**

In `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`, append the Russian translations. Keep `Platform API` / `Connect` / `Disconnect` in English to match the existing convention (tier names in English, action verbs translated where natural):

```
"section.apiCredits" = "API кредиты";
"settings.platformAPI" = "Platform API";
"settings.platformAPI.notConnected" = "Не подключено · баланс API скрыт";
"settings.platformAPI.connected" = "Подключено";
"settings.platformAPI.expired" = "Отключено · сессия истекла";
"settings.platformAPI.connect" = "Подключить";
"settings.platformAPI.disconnect" = "Отключить";
"settings.platformAPI.pasteManually" = "Вставить cookie вручную";
"settings.platformAPI.replaceKey" = "Заменить ключ…";
"settings.platformAPI.connectSheet.title" = "Подключение к platform.claude.com";
"settings.platformAPI.connectSheet.timeout" = "Время ожидания подключения истекло";
```

- [ ] **Step 3: Build to confirm no warnings**

Run: `swift build`

Expected: build succeeds with no warnings.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`

Expected: green.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings
git commit -m "feat(credits): localize Platform API section and API Credits row"
```

---

## Task 11: Manual UI smoke test

Per `CLAUDE.md`: UI changes must be verified end-to-end. Both auth paths must be exercised plus the disconnect flow and the platform-only expiry isolation.

**Files:** none modified.

- [ ] **Step 1: Build and run the app**

Run: `./scripts/run.sh`

Expected: ClaudeBar appears in the menu bar (do **not** use `swift run` — see `CLAUDE.md`).

- [ ] **Step 2: Verify the Settings section is in the Disconnected state**

Open Settings (gear icon → Settings…). Look at the new **Platform API** GroupBox.

Expected:
- Title bar reads "Platform API".
- Status row reads "Not connected · API balance hidden" with a `[Connect]` button.
- Disclosure "▾ Paste cookie manually" is collapsed.
- The popover (close Settings, click menu bar icon) shows usage rows but **no** API Credits row.

- [ ] **Step 3: Connect via WKWebView (one-tap path)**

Reopen Settings → click `[Connect]`.

Expected:
- A 640×720 modal sheet opens with `https://platform.claude.com/login` loaded inside.
- Cancel button in the top-right of the sheet.
- Sign in to platform.claude.com (use the credentials for an account that has prepaid API balance — i.e., one with an org carrying the `api` capability).

After successful login:
- Sheet auto-dismisses.
- Settings section transitions to "Connected · $X.XX" with `[Disconnect]` button.
- Open the popover — the **API Credits** row appears below the existing rows.

- [ ] **Step 4: Verify the menu bar text is unchanged**

Look at the menu bar icon's label.

Expected: still the 5h utilization percentage (e.g., `47%`). No `$` indicator.

- [ ] **Step 5: Verify cookie isolation (no Safari pollution)**

Open Safari → Preferences → Privacy → Manage Website Data → search "claude".

Expected: the cookie captured by the app is **not** present in Safari's data store. (The `WKWebsiteDataStore.nonPersistent()` ensures this.)

- [ ] **Step 6: Test platform-only expiry isolation**

In a terminal, manually corrupt the platform Keychain entry to simulate a 401:

```bash
security delete-generic-password -s com.claudebar -a platform_credentials || true
security add-generic-password -s com.claudebar -a platform_credentials -w "sk-ant-corrupted-value"
```

Quit and relaunch the app. Open the popover, then trigger `refreshUsage()` (wait for the next 5-min poll, or click the menu bar icon's refresh action if available).

Expected:
- Within one poll cycle, Settings transitions to "Not connected · API balance hidden" + `[Connect]`.
- The popover's API Credits row disappears.
- **claude.ai usage display is completely untouched** — no SetupView, no session-expired banner, usage rows still render. This is the critical regression guard for decision #8 in the spec.

- [ ] **Step 7: Test manual paste path**

In Settings → expand "▾ Paste cookie manually". Paste a known-good platform sessionKey value (capture from `platform.claude.com` DevTools in Safari/Chrome). Click `[Update]`.

Expected:
- Within one poll cycle (or immediately on the immediate refresh): Settings transitions to "Connected · $X.XX".
- API Credits row appears in the popover.

- [ ] **Step 8: Test disconnect**

Click `[Disconnect]` in the Platform API section.

Expected:
- Status row immediately returns to "Not connected · API balance hidden" + `[Connect]`.
- API Credits row disappears from the popover.
- The Keychain entry is gone:

```bash
security find-generic-password -s com.claudebar -a platform_credentials
# Expected: "The specified item could not be found in the keychain."
```

- [ ] **Step 9: Test 90-second timeout**

Click `[Connect]` again, then leave the sheet open without signing in for >90 seconds.

Expected:
- After ~90 seconds the sheet auto-dismisses.
- Settings section shows the orange "Connection timed out" message below the disclosure.

- [ ] **Step 10: Test bad manual paste**

Expand "▾ Paste cookie manually". Paste a value that doesn't start with `sk-ant-` (e.g., `garbage`). Click `[Update]`.

Expected:
- Inline red "Invalid session key" error appears below the field.
- Settings stays in the Disconnected state.
- No HTTP request is fired.

- [ ] **Step 11: Quit the app**

Use the gear menu → Quit, or `⌘Q` while the popover is focused.

- [ ] **Step 12: No commit**

This task changes no files. Skip the commit step.

---

## Self-Review Notes

Re-read the spec (`docs/superpowers/specs/2026-05-09-platform-credit-balance-v2-design.md`) and confirmed:

- **Spec coverage:**
  - Decision 1 (two acquisition paths, one stored credential) → Tasks 6+7 (WKWebView capture path) and Task 8 manual-paste field; both call `state.connectPlatform(sessionKey:)` from Task 5.
  - Decision 2 (strictly opt-in, no onboarding changes) → Onboarding files (`SetupView.swift`, `SessionKeyInputView.swift`) are not in the file inventory; they are intentionally untouched.
  - Decision 3 (Settings section: three render states) → Task 8 `platformStatusRow`.
  - Decision 4 (modal sheet hosting WKWebView) → Task 7.
  - Decision 5 (cookie capture via `didFinishNavigation`) → Task 6 `Coordinator`.
  - Decision 6 (90s timeout) → Task 7 `timeoutTask`.
  - Decision 7 (manual paste writes to same Keychain entry, same downstream pipeline) → Task 5 `connectPlatform(sessionKey:)` is the shared entry point; Task 8 paste field calls it.
  - Decision 8 (401/403 clears only platform key) → Task 3 `validatePlatformHTTPResponse` returns `PlatformAuthError.sessionExpired`; Task 5 `applyPlatformSessionExpired` clears only platform fields; Task 4 `handleSessionExpiredDoesNotTouchPlatformState` is the regression test.
  - Decision 9 (accept silently, no cross-account check) → no cross-account validation appears in any task; the connect path simply saves whatever cookie was captured.
  - Decision 10 (refresh piggybacks on `pollTimer` when connected) → Task 5 Step 5 wires the sibling `Task` into `refreshUsage()`; `refreshPlatformCredits()` no-ops when `platformSessionKey == nil`.
  - Decision 11 (single API org, first-match) → Task 5 `refreshPlatformCredits` filters by `capabilities.contains("api")` and takes the first.
  - Decision 12 (stale handling preserves last value) → Task 5 `markPlatformCreditsFetchFailed` only sets `isStale` when a value exists.
  - Acceptance criteria 1–8 → criterion 1 is Task 11 Step 2; criterion 2 is Task 11 Step 3; criterion 3 is Task 4 (Keychain account constant) + Task 11 Step 6 verification; criterion 4 is Task 11 Step 7; criterion 5 is Task 4 regression test + Task 11 Step 6; criterion 6 is Task 11 Step 8; criterion 7 is Task 11 Step 5; criterion 8 is the cumulative `swift test` runs across Tasks 1–10.

- **No placeholders:** Every code step shows the exact code; every command step shows the exact command.

- **Type/symbol consistency:**
  - `PlatformCredits` (Task 1) — used in Tasks 2–5, 8, 9.
  - `PlatformAuthError` (Task 2) — caught in Task 5 `refreshPlatformCredits`.
  - `platformSessionKey`, `platformCredits`, `platformCreditsIsStale`, `cachedPlatformOrgId` (Task 4) — referenced consistently in Tasks 5, 8, 9.
  - `platform_credentials` Keychain account name spelled the same way in Tasks 4, 5, and 11.
  - `connectPlatform(sessionKey:)` / `disconnectPlatform()` / `refreshPlatformCredits()` / `applyPlatformSessionExpired()` / `applyPlatformCreditsSuccess(_:)` / `markPlatformCreditsFetchFailed()` (Task 5) — referenced consistently in Tasks 7, 8.
  - `extractPlatformSessionKey(from:)` (Task 6) — single static helper, tested directly.
  - `fetchPlatformOrganizations(platformSessionKey:)` and `fetchPlatformCredits(platformSessionKey:platformOrgId:)` (Task 3) — match call sites in Task 5.
  - Localization keys (Task 10) match the `Text("…", bundle: .module)` references in Tasks 7, 8, 9.

- **Order constraint:** Tasks 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11. Task 1 introduces `PlatformCredits`. Task 2 adds parsers and `PlatformAuthError`. Task 3 adds fetch methods. Task 4 adds AppState properties + Keychain. Task 5 adds the connect/refresh flow (consumes Tasks 1–4). Task 6 adds the WKWebView wrapper. Task 7 adds the modal sheet (consumes Task 6). Task 8 adds the Settings UI (consumes Tasks 5, 7). Task 9 adds the popover row (consumes Tasks 1, 4). Task 10 adds localization (consumed by Tasks 7, 8, 9 — but the keys don't need to exist at compile time, they just render as literal until added; placing localization at Task 10 keeps the visual diff coherent without forcing a no-op build break). Task 11 verifies end-to-end.

- **Test count progression:** start 120 → +4 (T1) → +5 (T2) → +0 (T3) → +3 (T4) → +5 (T5) → +4 (T6) → +0 (T7) → +0 (T8) → +0 (T9) → +0 (T10) → +0 (T11) = **141 expected** at the end.
