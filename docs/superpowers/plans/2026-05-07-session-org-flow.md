# Session-key & Organization Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple session-key refresh, organization switching, and sign-out into three non-destructive flows so multi-org users can switch orgs without re-auth and session-key updates preserve context.

**Architecture:** Introduce `OrgListStore` for persisting the cached org list in UserDefaults. Split `AppState.clearCredentials()` into `signOut()` / `updateSessionKey(_:)` / `switchOrganization(to:)` and `confirmPendingOrg(_:)` / `cancelPendingOrgPick()` for the "wrong account" branch. Make session-expired recovery non-destructive (preserve `orgId` + `organizations`) so the reconnect screen names the org. Add a header `Menu` to `UsageDetailView` and rewrite the Settings session group as an inline form.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), Swift Testing framework (`@Test`), ViewInspector for view tests, UserDefaults for persistence, Keychain for credentials.

**Spec:** [`docs/superpowers/specs/2026-05-07-session-org-flow-design.md`](../specs/2026-05-07-session-org-flow-design.md)

---

## File Structure

**New files:**
- `Sources/ClaudeBarUI/Services/OrgListStore.swift` — `OrgListStore` protocol + `UserDefaultsOrgListStore` impl + `InMemoryOrgListStore` (for tests)
- `Tests/OrgListStoreTests.swift` — round-trip + isolation tests

**Modified files:**
- `Sources/ClaudeBarUI/Models/AppState.swift` — split credential lifecycle methods, add pending state, inject `OrgListStore`, persist `organizations`
- `Sources/ClaudeBarUI/Views/SettingsView.swift` — replace the single button with inline session-key form + org picker + Sign-out
- `Sources/ClaudeBarUI/Views/SessionExpiredView.swift` — personalize title with cached org name
- `Sources/ClaudeBarUI/Views/UsageDetailView.swift` — add header `Menu` for org switching
- `Sources/ClaudeBarUI/Views/SessionKeyInputView.swift` — call `switchOrganization` instead of removed `selectOrganization`
- `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` — new strings
- `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings` — new strings (parity)
- `Tests/AppStateTests.swift` — rename existing `clearCredentials` tests to `signOut`, add new tests
- `Tests/ViewTests.swift` — update assertions for new SettingsView layout, add coverage for personalized session-expired title and UsageDetailView header menu

---

## Task 1: Create OrgListStore protocol and UserDefaults implementation

**Files:**
- Create: `Sources/ClaudeBarUI/Services/OrgListStore.swift`
- Create: `Tests/OrgListStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/OrgListStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import ClaudeBarUI

@Suite
struct OrgListStoreTests {
    private func makeStore() -> UserDefaultsOrgListStore {
        let suite = UserDefaults(suiteName: "com.claudebar.test.orgs.\(UUID().uuidString)")!
        return UserDefaultsOrgListStore(defaults: suite, key: "organizations")
    }

    @Test func emptyByDefault() {
        let store = makeStore()
        #expect(store.load().isEmpty)
    }

    @Test func roundTripsOrganizations() {
        let store = makeStore()
        let orgs = [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
            Organization(uuid: "org-2", name: "Work", capabilities: ["claude_pro"]),
        ]
        store.save(orgs)
        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].uuid == "org-1")
        #expect(loaded[0].name == "Personal")
        #expect(loaded[1].uuid == "org-2")
        #expect(loaded[1].capabilities == ["claude_pro"])
    }

    @Test func saveOverwritesPrevious() {
        let store = makeStore()
        store.save([Organization(uuid: "old", name: "Old", capabilities: nil)])
        store.save([Organization(uuid: "new", name: "New", capabilities: nil)])
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].uuid == "new")
    }

    @Test func clearRemovesAll() {
        let store = makeStore()
        store.save([Organization(uuid: "x", name: "X", capabilities: nil)])
        store.clear()
        #expect(store.load().isEmpty)
    }

    @Test func corruptedDataReturnsEmpty() {
        let suite = UserDefaults(suiteName: "com.claudebar.test.orgs.\(UUID().uuidString)")!
        suite.set("not-json".data(using: .utf8), forKey: "organizations")
        let store = UserDefaultsOrgListStore(defaults: suite, key: "organizations")
        #expect(store.load().isEmpty)
    }

    @Test func inMemoryStoreRoundTrips() {
        let store = InMemoryOrgListStore()
        let orgs = [Organization(uuid: "x", name: "X", capabilities: nil)]
        store.save(orgs)
        #expect(store.load() == [Organization(uuid: "x", name: "X", capabilities: nil)])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OrgListStoreTests`
Expected: FAIL with "cannot find 'UserDefaultsOrgListStore' in scope"

- [ ] **Step 3: Add `Equatable` conformance to `Organization`**

Modify `Sources/ClaudeBarUI/Models/UsageModel.swift` — change line 76 declaration:

```swift
public struct Organization: Codable, Equatable {
    public let uuid: String
    public let name: String
    public let capabilities: [String]?

    public init(uuid: String, name: String, capabilities: [String]? = nil) {
        self.uuid = uuid
        self.name = name
        self.capabilities = capabilities
    }
}
```

(Just add `, Equatable` — the synthesized impl is enough since all stored properties are already Equatable.)

- [ ] **Step 4: Create OrgListStore.swift**

```swift
import Foundation

public protocol OrgListStore {
    func load() -> [Organization]
    func save(_ organizations: [Organization])
    func clear()
}

public final class UserDefaultsOrgListStore: OrgListStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.claudebar.organizations") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [Organization] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Organization].self, from: data)) ?? []
    }

    public func save(_ organizations: [Organization]) {
        guard let data = try? JSONEncoder().encode(organizations) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemoryOrgListStore: OrgListStore {
    private var storage: [Organization] = []

    public init(initial: [Organization] = []) {
        self.storage = initial
    }

    public func load() -> [Organization] { storage }
    public func save(_ organizations: [Organization]) { storage = organizations }
    public func clear() { storage = [] }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter OrgListStoreTests`
Expected: PASS (6 tests)

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Services/OrgListStore.swift \
        Sources/ClaudeBarUI/Models/UsageModel.swift \
        Tests/OrgListStoreTests.swift
git commit -m "feat(state): add OrgListStore for persisting org list to UserDefaults"
```

---

## Task 2: Inject OrgListStore into AppState and persist org list changes

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AppStateTests.swift` (near the other org tests, before line 222):

```swift
    // MARK: - Org List Persistence

    @Test func loadsOrgListFromStoreOnInit() {
        let store = InMemoryOrgListStore(initial: [
            Organization(uuid: "org-1", name: "Cached", capabilities: nil),
        ])
        let state = AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: store
        )
        #expect(state.organizations.count == 1)
        #expect(state.organizations[0].name == "Cached")
    }

    @Test func persistsOrgListWhenSet() {
        let store = InMemoryOrgListStore()
        let state = AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: store
        )
        state.organizations = [Organization(uuid: "org-1", name: "Saved", capabilities: nil)]
        #expect(store.load().count == 1)
        #expect(store.load()[0].name == "Saved")
    }
```

Update the existing `makeState()` helper (line 7-12) to inject an in-memory store so tests don't pollute UserDefaults:

```swift
    private func makeState(orgStore: OrgListStore = InMemoryOrgListStore()) -> AppState {
        let state = AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: orgStore
        )
        // Clean slate
        state.clearCredentials()
        return state
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL — "extra argument 'orgListStore' in call"

- [ ] **Step 3: Update AppState to accept and use OrgListStore**

In `Sources/ClaudeBarUI/Models/AppState.swift`:

Change the property declaration (line 9):

```swift
    public var organizations: [Organization] = [] {
        didSet { orgListStore.save(organizations) }
    }
```

Change the `Services` section (lines 32-35):

```swift
    // MARK: - Services
    private let keychain: KeychainService
    private let orgListStore: OrgListStore
    private var pollTimer: Timer?
    public var pollInterval: TimeInterval = 300 // 5 minutes
```

Change the initializer (lines 37-46):

```swift
    public init(
        keychain: KeychainService = KeychainService(),
        orgListStore: OrgListStore = UserDefaultsOrgListStore()
    ) {
        self.keychain = keychain
        self.orgListStore = orgListStore
        // Load cached orgs first so picker is instant on launch
        let cachedOrgs = orgListStore.load()
        if !cachedOrgs.isEmpty {
            // Bypass didSet to avoid redundant save of just-loaded data
            self._organizations = cachedOrgs
        }
        loadCredentials()
        if isAuthenticated {
            Task { @MainActor [weak self] in
                self?.startPolling()
            }
        }
    }
```

Note: Swift `@Observable` macros don't expose `_organizations` directly. Instead, do the load assignment inside an init helper that intentionally triggers `didSet` once — it's cheap (one UserDefaults write of identical data). Use this simpler form:

```swift
    public init(
        keychain: KeychainService = KeychainService(),
        orgListStore: OrgListStore = UserDefaultsOrgListStore()
    ) {
        self.keychain = keychain
        self.orgListStore = orgListStore
        self.organizations = orgListStore.load()  // triggers didSet, harmless idempotent save
        loadCredentials()
        if isAuthenticated {
            Task { @MainActor [weak self] in
                self?.startPolling()
            }
        }
    }
```

Update `clearCredentials()` (lines 85-92) to also clear the store:

```swift
    public func clearCredentials() {
        try? keychain.delete(account: Self.credentialsAccount)
        sessionKey = nil
        orgId = nil
        usage = nil
        organizationDetails = nil
        organizations = []  // didSet calls orgListStore.save([]) — equivalent to clear
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppStateTests`
Expected: PASS — including the two new tests and all existing tests still green

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(state): inject OrgListStore into AppState and persist org list"
```

---

## Task 3: Rename clearCredentials to signOut and make session-expired non-destructive

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AppStateTests.swift` in the "Org List Persistence" section:

```swift
    // MARK: - Sign Out & Session-Expired

    @Test func signOutWipesEverything() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
        state.organizations = [Organization(uuid: "org-1", name: "X", capabilities: nil)]
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )

        state.signOut()

        #expect(state.sessionKey == nil)
        #expect(state.orgId == nil)
        #expect(state.usage == nil)
        #expect(state.organizations.isEmpty)
        #expect(!state.isAuthenticated)
    }

    @Test func handleSessionExpiredPreservesOrgIdAndOrgs() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-old", orgId: "org-1")
        state.organizations = [Organization(uuid: "org-1", name: "Acme", capabilities: nil)]
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )

        state.handleSessionExpired()

        #expect(state.sessionKey == nil)
        #expect(state.orgId == "org-1")
        #expect(state.organizations.count == 1)
        #expect(state.organizations[0].name == "Acme")
        #expect(state.usage == nil)
        #expect(state.error == .sessionExpired)
        #expect(!state.isAuthenticated)
    }
```

Rename existing test at line 52 from `clearCredentialsResetsState` to `signOutResetsState` and update its body:

```swift
    @Test func signOutResetsState() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-test", orgId: "org-123")
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        state.organizations = [Organization(uuid: "org-123", name: "Test", capabilities: nil)]

        state.signOut()

        #expect(state.sessionKey == nil)
        #expect(state.orgId == nil)
        #expect(state.usage == nil)
        #expect(state.organizations.isEmpty)
        #expect(!state.isAuthenticated)
    }
```

Update the `makeState()` helper (line 7) to call `signOut()` instead:

```swift
    private func makeState(orgStore: OrgListStore = InMemoryOrgListStore()) -> AppState {
        let state = AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: orgStore
        )
        state.signOut()
        return state
    }
```

Update `saveAndLoadCredentials` (line 33) — change the cleanup call at line 49 from `state2.clearCredentials()` to `state2.signOut()`.

Update `selectOrganizationSavesCredentials` (line 200) — change the cleanup at line 210 from `state.clearCredentials()` to `state.signOut()`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL — "value of type 'AppState' has no member 'signOut'"

- [ ] **Step 3: Rename clearCredentials → signOut and add handleSessionExpired**

In `Sources/ClaudeBarUI/Models/AppState.swift`:

Rename `clearCredentials()` (lines 85-92) to `signOut()` — keep the body identical:

```swift
    public func signOut() {
        try? keychain.delete(account: Self.credentialsAccount)
        sessionKey = nil
        orgId = nil
        usage = nil
        organizationDetails = nil
        organizations = []
    }
```

Add a new `handleSessionExpired()` method (insert after `signOut`):

```swift
    /// Non-destructive recovery: wipes sessionKey + usage but preserves
    /// orgId and cached organizations so the reconnect screen can name the org.
    public func handleSessionExpired() {
        try? keychain.delete(account: Self.credentialsAccount)
        sessionKey = nil
        usage = nil
        organizationDetails = nil
        error = .sessionExpired
        // orgId and organizations: preserved
    }
```

Update `refreshUsage()` — change line 138-140 from:

```swift
        } catch APIError.sessionExpired {
            error = .sessionExpired
            clearCredentials()
```

to:

```swift
        } catch APIError.sessionExpired {
            handleSessionExpired()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppStateTests`
Expected: PASS — all existing tests + the two new tests

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "refactor(state): rename clearCredentials to signOut; non-destructive session-expired"
```

---

## Task 4: Add switchOrganization and unify org-selection call sites

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift`
- Modify: `Sources/ClaudeBarUI/Views/SessionKeyInputView.swift`
- Modify: `Tests/AppStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AppStateTests.swift` after the "Sign Out & Session-Expired" section:

```swift
    // MARK: - Switch Organization

    @Test func switchOrganizationSavesAndClearsStaleUsage() async throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk", orgId: "org-1")
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        state.organizationDetails = OrganizationDetails(
            uuid: "org-1", name: "Old", rateLimitTier: "max5x"
        )

        // Don't actually start polling in tests — just verify state mutations
        state.stopPolling()
        let newOrg = Organization(uuid: "org-2", name: "New", capabilities: nil)
        await state.switchOrganization(to: newOrg)

        #expect(state.orgId == "org-2")
        #expect(state.usage == nil)
        #expect(state.organizationDetails == nil)
        #expect(state.sessionKey == "sk")  // unchanged

        state.signOut()
    }

    @Test func switchOrganizationDoesNothingWithoutSessionKey() async {
        let state = makeState()
        // No sessionKey set
        let org = Organization(uuid: "org-2", name: "New", capabilities: nil)
        await state.switchOrganization(to: org)

        #expect(state.orgId == nil, "Should not save orgId without sessionKey")
    }
```

Replace the existing `selectOrganizationSavesCredentials` test (line 200-211) with:

```swift
    @Test func switchOrganizationSavesCredentials() async throws {
        let state = makeState()
        state.sessionKey = "sk-ant-test"
        state.stopPolling()

        let org = Organization(uuid: "org-2", name: "Work", capabilities: nil)
        await state.switchOrganization(to: org)

        #expect(state.sessionKey == "sk-ant-test")
        #expect(state.orgId == "org-2")
        #expect(state.isAuthenticated)

        state.signOut()
    }
```

Add `OrganizationDetails: Equatable` conformance check — if not already there, the test references `state.organizationDetails == nil` which works for Optional. Skip if already passes.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL — "value of type 'AppState' has no member 'switchOrganization'"

- [ ] **Step 3: Replace `selectOrganization` with `switchOrganization` in AppState**

In `Sources/ClaudeBarUI/Models/AppState.swift`, replace the `selectOrganization` method (lines 116-124):

```swift
    /// Switch to a different organization while keeping the current sessionKey.
    /// Clears stale usage/tier data (tier may differ between orgs) and triggers
    /// a fresh fetch via startPolling().
    public func switchOrganization(to org: Organization) async {
        guard let sessionKey else { return }
        usage = nil
        organizationDetails = nil
        do {
            try saveCredentials(sessionKey: sessionKey, orgId: org.uuid)
            startPolling()
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
```

- [ ] **Step 4: Update SessionKeyInputView call site**

In `Sources/ClaudeBarUI/Views/SessionKeyInputView.swift` (line 71), change:

```swift
                    Task { await state.selectOrganization(org) }
```

to:

```swift
                    Task { await state.switchOrganization(to: org) }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — full suite including new switchOrganization tests + existing view tests still green

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift \
        Sources/ClaudeBarUI/Views/SessionKeyInputView.swift \
        Tests/AppStateTests.swift
git commit -m "refactor(state): replace selectOrganization with switchOrganization"
```

---

## Task 5: Add updateSessionKey with pending-org-pick state machine

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

This task introduces a network call inside `updateSessionKey` that uses the static `ClaudeAPIClient.fetchOrganizations`. Since we can't easily mock that without an injection seam, **we test the state-machine pieces directly** using `applyKeyUpdateResult` (a pure helper that mutates state given an already-fetched org list). The full method is then a thin wrapper that calls the helper.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AppStateTests.swift` after the "Switch Organization" section:

```swift
    // MARK: - Update Session Key

    @Test func applyKeyUpdateResultPreservesOrgIdWhenStillValid() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-old", orgId: "org-1")
        state.organizations = [Organization(uuid: "org-1", name: "Old", capabilities: nil)]
        state.stopPolling()

        let newOrgs = [
            Organization(uuid: "org-1", name: "Renamed", capabilities: nil),
            Organization(uuid: "org-2", name: "Other", capabilities: nil),
        ]
        state.applyKeyUpdateResult(newSessionKey: "sk-new", fetchedOrgs: newOrgs)

        #expect(state.sessionKey == "sk-new")
        #expect(state.orgId == "org-1")
        #expect(state.organizations.count == 2)
        #expect(!state.pendingOrgPick)

        state.signOut()
    }

    @Test func applyKeyUpdateResultEntersPendingPickWhenOrgMissing() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-old", orgId: "org-1")
        state.organizations = [Organization(uuid: "org-1", name: "Old", capabilities: nil)]
        state.stopPolling()

        let newOrgs = [
            Organization(uuid: "org-2", name: "Different", capabilities: nil),
            Organization(uuid: "org-3", name: "Also", capabilities: nil),
        ]
        state.applyKeyUpdateResult(newSessionKey: "sk-new", fetchedOrgs: newOrgs)

        // Old creds intact in keychain
        #expect(state.sessionKey == "sk-old")
        #expect(state.orgId == "org-1")
        // Pending state populated
        #expect(state.pendingOrgPick)
        #expect(state.pendingSessionKey == "sk-new")
        #expect(state.pendingOrganizations.count == 2)
        // Cached orgs NOT touched yet
        #expect(state.organizations.count == 1)
        #expect(state.organizations[0].name == "Old")

        state.signOut()
    }

    @Test func confirmPendingOrgCommitsAndClearsPending() async throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-old", orgId: "org-1")
        state.stopPolling()

        // Simulate pending state
        state.pendingSessionKey = "sk-new"
        state.pendingOrganizations = [Organization(uuid: "org-7", name: "New", capabilities: nil)]
        state.pendingOrgPick = true

        await state.confirmPendingOrg(Organization(uuid: "org-7", name: "New", capabilities: nil))

        #expect(state.sessionKey == "sk-new")
        #expect(state.orgId == "org-7")
        #expect(state.organizations.count == 1)
        #expect(state.organizations[0].uuid == "org-7")
        #expect(!state.pendingOrgPick)
        #expect(state.pendingSessionKey == nil)
        #expect(state.pendingOrganizations.isEmpty)

        state.signOut()
    }

    @Test func cancelPendingOrgPickRevertsTransientState() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-old", orgId: "org-1")

        state.pendingSessionKey = "sk-new"
        state.pendingOrganizations = [Organization(uuid: "org-2", name: "X", capabilities: nil)]
        state.pendingOrgPick = true

        state.cancelPendingOrgPick()

        #expect(state.sessionKey == "sk-old")
        #expect(state.orgId == "org-1")
        #expect(!state.pendingOrgPick)
        #expect(state.pendingSessionKey == nil)
        #expect(state.pendingOrganizations.isEmpty)

        state.signOut()
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL — "value of type 'AppState' has no member 'pendingOrgPick'"

- [ ] **Step 3: Add pending state and update-session-key methods to AppState**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add the pending properties to the auth-state section (after line 9):

```swift
    // MARK: - Auth State
    public var sessionKey: String?
    public var orgId: String?
    public var organizations: [Organization] = [] {
        didSet { orgListStore.save(organizations) }
    }
    public var isAuthenticated: Bool { sessionKey != nil && orgId != nil }

    // MARK: - Pending Key-Update State
    /// Set while the user is updating their session key and the new key
    /// belongs to a different account (current orgId is not in the new org list).
    /// While true, polling is paused and the Settings UI shows an inline picker.
    public var pendingOrgPick: Bool = false
    public var pendingSessionKey: String?
    public var pendingOrganizations: [Organization] = []
```

Add the new methods near `switchOrganization` in the API Calls section:

```swift
    /// Validate a new session key by fetching the org list, then either
    /// preserve the current orgId (if still in the list) or enter a pending
    /// pick state that holds the new key transiently until the user confirms.
    public func updateSessionKey(_ newKey: String) async {
        isLoading = true
        error = nil
        do {
            let fetched = try await ClaudeAPIClient.fetchOrganizations(sessionKey: newKey)
            applyKeyUpdateResult(newSessionKey: newKey, fetchedOrgs: fetched)
        } catch let apiError as APIError {
            error = .api(apiError)
        } catch {
            self.error = .network(error.localizedDescription)
        }
        isLoading = false
    }

    /// Pure state-machine step extracted from updateSessionKey for testability.
    /// Decides between "preserve current org" and "enter pending pick".
    public func applyKeyUpdateResult(newSessionKey: String, fetchedOrgs: [Organization]) {
        if let currentOrgId = orgId, fetchedOrgs.contains(where: { $0.uuid == currentOrgId }) {
            // Common case: cookie rotated, account/org unchanged
            do {
                try saveCredentials(sessionKey: newSessionKey, orgId: currentOrgId)
                organizations = fetchedOrgs
                startPolling()
            } catch {
                self.error = .network(error.localizedDescription)
            }
        } else {
            // Different account: hold new key transiently, wait for user pick
            stopPolling()
            pendingSessionKey = newSessionKey
            pendingOrganizations = fetchedOrgs
            pendingOrgPick = true
        }
    }

    /// Commit the held sessionKey + the picked org atomically, then resume polling.
    public func confirmPendingOrg(_ org: Organization) async {
        guard let pending = pendingSessionKey else { return }
        do {
            try saveCredentials(sessionKey: pending, orgId: org.uuid)
            organizations = pendingOrganizations
            usage = nil
            organizationDetails = nil
            pendingSessionKey = nil
            pendingOrganizations = []
            pendingOrgPick = false
            startPolling()
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

    /// Discard pending key/org state. Old credentials are untouched.
    public func cancelPendingOrgPick() {
        pendingSessionKey = nil
        pendingOrganizations = []
        pendingOrgPick = false
        if isAuthenticated {
            startPolling()
        }
    }
```

Also extend `signOut()` to clear pending state:

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
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppStateTests`
Expected: PASS — all existing tests + four new updateSessionKey tests

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(state): add updateSessionKey with pending-org-pick state machine"
```

---

## Task 6: Add localization strings (en + ru) for new UI

**Files:**
- Modify: `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`

- [ ] **Step 1: Append new English strings**

Add to `Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings` (alphabetical-ish order matching existing style):

```
"action.cancel" = "Cancel";
"action.signOut" = "Sign out";
"action.update" = "Update";
"header.updateSessionKey" = "Update session key…";
"header.openSettings" = "Settings…";
"session.reconnect %@" = "Reconnect %@";
"settings.connectedAs %@" = "Connected as %@";
"settings.organization" = "Organization:";
"settings.sessionKey" = "Session key:";
"update.badKey" = "Invalid session key";
"update.wrongAccount" = "This key belongs to a different account. Pick org:";
```

- [ ] **Step 2: Append parity Russian strings**

Add to `Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings`:

```
"action.cancel" = "Отмена";
"action.signOut" = "Выйти";
"action.update" = "Обновить";
"header.updateSessionKey" = "Обновить ключ сессии…";
"header.openSettings" = "Настройки…";
"session.reconnect %@" = "Переподключить %@";
"settings.connectedAs %@" = "Подключено как %@";
"settings.organization" = "Организация:";
"settings.sessionKey" = "Ключ сессии:";
"update.badKey" = "Неверный ключ сессии";
"update.wrongAccount" = "Этот ключ принадлежит другому аккаунту. Выберите организацию:";
```

- [ ] **Step 3: Verify the bundle still builds**

Run: `swift build`
Expected: build succeeds with no warnings

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeBarUI/Resources/en.lproj/Localizable.strings \
        Sources/ClaudeBarUI/Resources/ru.lproj/Localizable.strings
git commit -m "i18n: add strings for new session/org Settings UI"
```

---

## Task 7: Rewrite SettingsView session group as inline form

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/SettingsView.swift`
- Modify: `Tests/ViewTests.swift`

The new session group has: status indicator + "Connected as <Org>", session key field with masked dots + Update button, org picker (when >1 org), Sign out button.

- [ ] **Step 1: Update view tests**

In `Tests/ViewTests.swift`, replace the existing `SettingsViewTests` suite (lines 219-275). Key changes: the old "Update Session Key" button is gone; instead we have a session-key text field, an Update button, an org name display, and a Sign-out button.

```swift
@MainActor
@Suite
struct SettingsViewTests {
    private func makeState() -> AppState {
        AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: InMemoryOrgListStore()
        )
    }

    @Test func showsTitle() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Settings")
    }

    @Test func showsDisconnectedWhenNotAuthenticated() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Not connected")
    }

    @Test func showsConnectedAsOrgNameWhenAuthenticated() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        state.organizations = [Organization(uuid: "org-123", name: "Acme", capabilities: nil)]
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Connected as Acme")
    }

    @Test func showsSessionKeyFieldWhenAuthenticated() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.SecureField.self)
    }

    @Test func showsUpdateButtonWhenAuthenticated() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(button: "Update")
    }

    @Test func showsSignOutButtonWhenAuthenticated() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(button: "Sign out")
    }

    @Test func showsOrgPickerWhenMultipleOrgs() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-1"
        state.organizations = [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
            Organization(uuid: "org-2", name: "Work", capabilities: nil),
        ]
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Organization:")
    }

    @Test func hidesOrgPickerForSingleOrg() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-1"
        state.organizations = [Organization(uuid: "org-1", name: "Solo", capabilities: nil)]
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        #expect(throws: (any Error).self) { try inspected.find(text: "Organization:") }
    }

    @Test func showsPendingOrgPickerInWrongAccountState() throws {
        let state = makeState()
        state.sessionKey = "sk-old"
        state.orgId = "org-1"
        state.pendingSessionKey = "sk-new"
        state.pendingOrganizations = [
            Organization(uuid: "org-9", name: "DifferentAccount", capabilities: nil),
        ]
        state.pendingOrgPick = true
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "This key belongs to a different account. Pick org:")
        _ = try inspected.find(text: "DifferentAccount")
    }

    @Test func showsQuitButton() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(button: "Quit ClaudeBar")
    }

    @Test func showsDoneButton() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(button: "Done")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsViewTests`
Expected: FAIL — "Connected as Acme" not found, etc.

- [ ] **Step 3: Rewrite SettingsView body**

Replace `Sources/ClaudeBarUI/Views/SettingsView.swift` entirely:

```swift
import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    @Bindable public var state: AppState

    @State private var keyDraft: String = ""
    @State private var inlineKeyError: String?

    public init(state: AppState) { self.state = state }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("settings.title", bundle: .module)
                    .font(.headline)
                Spacer()
                Button {
                    state.showingSettings = false
                } label: {
                    Text("action.done", bundle: .module)
                }
                .modifier(BorderedButtonModifier())
                .controlSize(.small)
            }

            sessionGroup

            // Launch at login
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LaunchAtLoginToggle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } label: {
                Text("settings.general", bundle: .module)
            }

            Spacer()

            Divider()
            QuitButton()
        }
        .padding(16)
        .frame(width: 320, height: 360)
    }

    @ViewBuilder
    private var sessionGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                connectionStatusLine

                if state.isAuthenticated && !state.pendingOrgPick {
                    sessionKeyEditor
                    if state.organizations.count > 1 {
                        orgPicker
                    }
                    Button {
                        state.signOut()
                    } label: {
                        Text("action.signOut", bundle: .module)
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                if state.pendingOrgPick {
                    pendingPickPrompt
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Text("settings.session", bundle: .module)
        }
    }

    @ViewBuilder
    private var connectionStatusLine: some View {
        HStack {
            Circle()
                .fill(state.isAuthenticated ? .green : .red)
                .frame(width: 8, height: 8)
            if state.isAuthenticated, let orgName = currentOrgName() {
                Text("settings.connectedAs \(orgName)", bundle: .module)
                    .font(.subheadline)
            } else if state.isAuthenticated {
                Text("settings.connected", bundle: .module)
                    .font(.subheadline)
            } else {
                Text("settings.notConnected", bundle: .module)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var sessionKeyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.sessionKey", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                SecureField("", text: $keyDraft, prompt: Text("setup.sessionKeyPlaceholder", bundle: .module))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button {
                    inlineKeyError = nil
                    Task {
                        await state.updateSessionKey(keyDraft)
                        if case .api(let apiErr) = state.error, apiErr == .sessionExpired {
                            inlineKeyError = String(localized: "update.badKey", bundle: .module)
                        } else {
                            keyDraft = ""
                        }
                    }
                } label: {
                    Text("action.update", bundle: .module)
                }
                .modifier(BorderedButtonModifier())
                .controlSize(.small)
                .disabled(keyDraft.isEmpty || state.isLoading)
            }
            if let inlineKeyError {
                Text(inlineKeyError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var orgPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.organization", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("", selection: orgSelectionBinding) {
                ForEach(state.organizations, id: \.uuid) { org in
                    Text(org.name).tag(org.uuid as String?)
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var pendingPickPrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("update.wrongAccount", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.orange)
            ForEach(state.pendingOrganizations, id: \.uuid) { org in
                Button {
                    Task { await state.confirmPendingOrg(org) }
                } label: {
                    Text(org.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                state.cancelPendingOrgPick()
                keyDraft = ""
            } label: {
                Text("action.cancel", bundle: .module)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func currentOrgName() -> String? {
        guard let orgId = state.orgId else { return nil }
        return state.organizations.first(where: { $0.uuid == orgId })?.name
    }

    private var orgSelectionBinding: Binding<String?> {
        Binding(
            get: { state.orgId },
            set: { newValue in
                guard let uuid = newValue,
                      uuid != state.orgId,
                      let org = state.organizations.first(where: { $0.uuid == uuid }) else { return }
                Task { await state.switchOrganization(to: org) }
            }
        )
    }
}

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(isOn: $launchAtLogin) {
            Text("settings.launchAtLogin", bundle: .module)
        }
        .font(.subheadline)
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = !newValue
            }
        }
    }
}

#Preview("Settings - Connected") {
    let state = AppState(
        keychain: KeychainService(serviceName: "com.claudebar.preview"),
        orgListStore: InMemoryOrgListStore(initial: [
            Organization(uuid: "fake-org", name: "Acme Inc", capabilities: nil)
        ])
    )
    state.sessionKey = "fake-key"
    state.orgId = "fake-org"
    state.organizations = [Organization(uuid: "fake-org", name: "Acme Inc", capabilities: nil)]
    return SettingsView(state: state)
}

#Preview("Settings - Multi-Org") {
    let state = AppState(
        keychain: KeychainService(serviceName: "com.claudebar.preview"),
        orgListStore: InMemoryOrgListStore()
    )
    state.sessionKey = "fake-key"
    state.orgId = "org-1"
    state.organizations = [
        Organization(uuid: "org-1", name: "Personal", capabilities: nil),
        Organization(uuid: "org-2", name: "Work", capabilities: nil),
    ]
    return SettingsView(state: state)
}

#Preview("Settings - Disconnected") {
    SettingsView(state: AppState(
        keychain: KeychainService(serviceName: "com.claudebar.preview"),
        orgListStore: InMemoryOrgListStore()
    ))
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsViewTests`
Expected: PASS — all 11 tests

Run: `swift test`
Expected: full suite green

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Views/SettingsView.swift Tests/ViewTests.swift
git commit -m "feat(ui): rewrite Settings session group as inline form with org picker"
```

---

## Task 8: Personalize SessionExpiredView title with cached org name

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/SessionExpiredView.swift`
- Modify: `Tests/ViewTests.swift`

- [ ] **Step 1: Update view tests**

In `Tests/ViewTests.swift`, replace the existing `SessionExpiredViewTests` suite (lines 142-171):

```swift
@MainActor
@Suite
struct SessionExpiredViewTests {
    private func makeState() -> AppState {
        AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: InMemoryOrgListStore()
        )
    }

    @Test func showsGenericTitleWhenNoOrgCached() throws {
        let state = makeState()
        let view = SessionExpiredView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Session Expired")
    }

    @Test func showsOrgNameInTitleWhenCached() throws {
        let state = makeState()
        state.orgId = "org-123"
        state.organizations = [Organization(uuid: "org-123", name: "Acme", capabilities: nil)]
        let view = SessionExpiredView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Reconnect Acme")
    }

    @Test func showsReconnectButton() throws {
        let state = makeState()
        let view = SessionExpiredView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(button: "Reconnect")
    }

    @Test func showsKeyInputField() throws {
        let state = makeState()
        let view = SessionExpiredView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.TextField.self)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionExpiredViewTests`
Expected: FAIL — "Reconnect Acme" not found

- [ ] **Step 3: Update SessionExpiredView**

Replace `Sources/ClaudeBarUI/Views/SessionExpiredView.swift`:

```swift
import SwiftUI

public struct SessionExpiredView: View {
    public let state: AppState

    public init(state: AppState) { self.state = state }

    public var body: some View {
        SessionKeyInputView(
            state: state,
            title: titleString,
            subtitle: String(localized: "session.expiredSubtitle", bundle: .module),
            buttonLabel: String(localized: "action.reconnect", bundle: .module),
            titleIcon: "exclamationmark.triangle",
            titleColor: .orange
        )
    }

    private var titleString: String {
        if let orgId = state.orgId,
           let name = state.organizations.first(where: { $0.uuid == orgId })?.name {
            return String(localized: "session.reconnect \(name)", bundle: .module)
        }
        return String(localized: "session.expired", bundle: .module)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionExpiredViewTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Views/SessionExpiredView.swift Tests/ViewTests.swift
git commit -m "feat(ui): personalize session-expired title with cached org name"
```

---

## Task 9: Add org switcher Menu to UsageDetailView header

**Files:**
- Modify: `Sources/ClaudeBarUI/Views/UsageDetailView.swift`
- Modify: `Tests/ViewTests.swift`

The existing header is `Text("Claude Usage") + tier pill`. We replace the title `Text` with: an org Menu when `organizations.count > 1`, otherwise a plain Text showing the current org name (falling back to "Claude Usage" when no name resolves).

- [ ] **Step 1: Add view tests**

In `Tests/ViewTests.swift`, add a new suite (place it after `SessionExpiredViewTests`):

```swift
// MARK: - UsageDetailView Header Tests

@MainActor
@Suite
struct UsageDetailViewHeaderTests {
    private func makeAuthedState(orgs: [Organization]) -> AppState {
        let state = AppState(
            keychain: KeychainService(serviceName: "com.claudebar.test"),
            orgListStore: InMemoryOrgListStore()
        )
        state.signOut()
        state.sessionKey = "sk"
        state.orgId = orgs.first?.uuid
        state.organizations = orgs
        return state
    }

    @Test func showsCurrentOrgNameInHeader() throws {
        let state = makeAuthedState(orgs: [
            Organization(uuid: "org-1", name: "Acme", capabilities: nil),
        ])
        let view = UsageDetailView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Acme")
    }

    @Test func showsMenuWhenMultipleOrgs() throws {
        let state = makeAuthedState(orgs: [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
            Organization(uuid: "org-2", name: "Work", capabilities: nil),
        ])
        let view = UsageDetailView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.Menu.self)
    }

    @Test func noMenuForSingleOrg() throws {
        let state = makeAuthedState(orgs: [
            Organization(uuid: "org-1", name: "Solo", capabilities: nil),
        ])
        let view = UsageDetailView(state: state)
        let inspected = try view.inspect()
        #expect(throws: (any Error).self) { try inspected.find(ViewType.Menu.self) }
    }

    @Test func fallsBackToTitleWhenNoOrgName() throws {
        let state = makeAuthedState(orgs: [])
        let view = UsageDetailView(state: state)
        let inspected = try view.inspect()
        _ = try inspected.find(text: "Claude Usage")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageDetailViewHeaderTests`
Expected: FAIL — Menu not found, etc.

- [ ] **Step 3: Replace the header in UsageDetailView**

In `Sources/ClaudeBarUI/Views/UsageDetailView.swift`, replace the `header` computed property (lines 43-54):

```swift
    private var header: some View {
        HStack {
            headerTitle
            Spacer()
            if state.usage != nil {
                tierPill(for: state.tier)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var headerTitle: some View {
        let currentOrgName = state.orgId.flatMap { id in
            state.organizations.first(where: { $0.uuid == id })?.name
        }
        if state.organizations.count > 1, let name = currentOrgName {
            Menu {
                ForEach(state.organizations.filter { $0.uuid != state.orgId }, id: \.uuid) { org in
                    Button(org.name) {
                        Task { await state.switchOrganization(to: org) }
                    }
                }
                Divider()
                Button {
                    state.showingSettings = true
                } label: {
                    Text("header.updateSessionKey", bundle: .module)
                }
                Button {
                    state.showingSettings = true
                } label: {
                    Text("header.openSettings", bundle: .module)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else if let name = currentOrgName {
            Text(name).font(.headline)
        } else {
            Text("usage.title", bundle: .module).font(.headline)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageDetailViewHeaderTests`
Expected: PASS — 4 tests

Run: `swift test`
Expected: full suite green

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Views/UsageDetailView.swift Tests/ViewTests.swift
git commit -m "feat(ui): add org switcher Menu to UsageDetailView header"
```

---

## Task 10: Refresh org list in background after each successful poll

**Files:**
- Modify: `Sources/ClaudeBarUI/Models/AppState.swift`
- Modify: `Tests/AppStateTests.swift`

The spec calls for refreshing the org list periodically so the cache stays fresh. We piggyback on `refreshUsage` — after a successful `fetchUsage()`, kick off `ClaudeAPIClient.fetchOrganizations` in the background and update the cache. No TTL gate — usage polls already throttled to 5min, so org-list refresh ≤ once per 5min is fine.

- [ ] **Step 1: Add a test that verifies the helper updates the cache**

We can't easily mock `ClaudeAPIClient.fetchOrganizations` (static). Test the seam: a helper method `applyRefreshedOrgList(_:)` that takes a fetched array and replaces `organizations`.

Add to `Tests/AppStateTests.swift` after the "Update Session Key" tests:

```swift
    // MARK: - Background Org-List Refresh

    @Test func applyRefreshedOrgListReplacesCache() {
        let state = makeState()
        state.organizations = [Organization(uuid: "old", name: "Old", capabilities: nil)]
        let refreshed = [
            Organization(uuid: "old", name: "Renamed", capabilities: nil),
            Organization(uuid: "new", name: "Added", capabilities: nil),
        ]
        state.applyRefreshedOrgList(refreshed)
        #expect(state.organizations.count == 2)
        #expect(state.organizations[0].name == "Renamed")
    }

    @Test func applyRefreshedOrgListIgnoresEmptyResponse() {
        let state = makeState()
        state.organizations = [Organization(uuid: "x", name: "Keep", capabilities: nil)]
        state.applyRefreshedOrgList([])
        // Don't blow away cache on a transient empty response
        #expect(state.organizations.count == 1)
        #expect(state.organizations[0].name == "Keep")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL — "no member 'applyRefreshedOrgList'"

- [ ] **Step 3: Add the helper and wire it into refreshUsage**

In `Sources/ClaudeBarUI/Models/AppState.swift`, add inside the API Calls section near `refreshUsage`:

```swift
    /// Replace the cached org list with a fresh server response.
    /// Empty responses are ignored to avoid wiping the cache on a transient blip.
    public func applyRefreshedOrgList(_ fetched: [Organization]) {
        guard !fetched.isEmpty else { return }
        organizations = fetched
    }
```

Update `refreshUsage()` to fire the background refresh after a successful fetch. Replace the body (lines 126-147) with:

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
            // Background refresh of the org list — best-effort, non-fatal
            Task { [weak self, sessionKey] in
                if let fetched = try? await ClaudeAPIClient.fetchOrganizations(sessionKey: sessionKey) {
                    await MainActor.run { self?.applyRefreshedOrgList(fetched) }
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppStateTests`
Expected: PASS — including the two new tests

Run: `swift test`
Expected: full suite green

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarUI/Models/AppState.swift Tests/AppStateTests.swift
git commit -m "feat(state): refresh org list in background after each successful poll"
```

---

## Task 11: Manual verification on the running app

**Files:** none (smoke test)

- [ ] **Step 1: Build and run**

Run: `./scripts/run.sh`
Expected: app launches, menu bar icon appears, popover opens

- [ ] **Step 2: Verify update-session-key flow (single-account case)**

1. Open Settings (gear icon in popover footer)
2. Status reads "Connected as <Your Org>"
3. Paste a freshly-rotated sessionKey from claude.ai DevTools into the Session key field
4. Click Update
5. Expected: Status stays "Connected as <Your Org>", no view transition, usage continues polling

- [ ] **Step 3: Verify org switching (multi-org accounts only)**

1. Click the org name in the popover header → Menu opens listing other orgs
2. Pick another org → header label updates, usage panel reloads, Settings still shows the new org name
3. Switch back from Settings → org picker dropdown also reflects the change

- [ ] **Step 4: Verify session-expired recovery**

1. Manually delete the sessionKey cookie on claude.ai (DevTools → Application → Cookies → delete `sessionKey`) so the next poll fails
2. Wait for next poll (or click Refresh)
3. Expected: popover shows "Reconnect *<Your Org>*" — not the generic "Setup ClaudeBar" screen
4. Paste a fresh sessionKey → returns directly to the usage view, no org re-pick

- [ ] **Step 5: Verify sign out**

1. Settings → click "Sign out" (less-prominent text button)
2. Expected: popover shows the original "Setup ClaudeBar" first-run screen

- [ ] **Step 6: Commit any small fixes from manual testing, then merge**

If any issue surfaces, fix it as a small follow-up commit referencing this task. If everything works, no extra commit needed.

---

## Self-Review Notes

Spec coverage check:

| Spec section | Implementing task |
|---|---|
| State model — `organizations` persisted to UserDefaults | Task 1 + 2 |
| State model — `signOut()` | Task 3 |
| State model — `updateSessionKey(_:)` | Task 5 |
| State model — `switchOrganization(to:)` | Task 4 |
| State model — `confirmPendingOrg` / `cancelPendingOrgPick` | Task 5 |
| Flow A — preserve orgId when valid | Task 5 |
| Flow A — pending pick when org missing | Task 5 |
| Flow B — header menu / Settings picker switching | Tasks 7, 9 |
| Flow C — non-destructive session expired | Task 3 |
| Background org-list refresh | Task 10 |
| `UsageDetailView` header Menu | Task 9 |
| `SettingsView` inline form | Task 7 |
| `SessionExpiredView` personalized title | Task 8 |
| Localization strings (en + ru) | Task 6 |
| Migration (no destructive data loss) | Built into Task 2 (init loads cache) |
| Tests: AppState + cache + view | Tasks 1, 2, 3, 4, 5, 7, 8, 9, 10 |
| Manual smoke | Task 11 |

All spec requirements have a corresponding task. Type names are consistent throughout (`OrgListStore`, `UserDefaultsOrgListStore`, `InMemoryOrgListStore`, `signOut`, `switchOrganization`, `updateSessionKey`, `applyKeyUpdateResult`, `confirmPendingOrg`, `cancelPendingOrgPick`, `handleSessionExpired`, `applyRefreshedOrgList`).
