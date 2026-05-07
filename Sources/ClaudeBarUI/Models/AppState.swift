import SwiftUI

@MainActor
@Observable
public final class AppState {
    // MARK: - Auth State
    public var sessionKey: String?
    public var orgId: String?
    public var organizations: [Organization] = [] {
        didSet { orgListStore.save(organizations) }
    }
    public var isAuthenticated: Bool { sessionKey != nil && orgId != nil }

    /// Subset of `organizations` shown in switcher UIs. Hides free/individual
    /// orgs (no paid capability marker) since their usage is not tracked here.
    /// The currently-active org is always kept visible so the user can navigate
    /// out of it even if it happens to be unpaid.
    public var visibleOrganizations: [Organization] {
        organizations.filter { $0.isPaidPlan || $0.uuid == orgId }
    }

    // MARK: - Pending Key-Update State
    /// Set while the user is updating their session key and the new key
    /// belongs to a different account (current orgId is not in the new org list).
    /// While true, polling is paused and the Settings UI shows an inline picker.
    public var pendingOrgPick: Bool = false
    public var pendingSessionKey: String?
    public var pendingOrganizations: [Organization] = []

    // MARK: - Usage State
    public var usage: UsageResponse?
    public var organizationDetails: OrganizationDetails?
    public var lastUpdated: Date?
    public var isLoading = false
    public var error: AppError?

    /// Authoritative tier from `/organizations/{id}` when available; falls
    /// back to a heuristic on the usage payload during the first-load window.
    public var tier: SubscriptionTier {
        if let details = organizationDetails { return details.tier }
        return (usage?.isMaxTier ?? false) ? .max5x : .pro
    }

    // MARK: - UI State
    public var showingSettings = false

    // MARK: - Update State
    public var availableUpdate: (version: String, url: String)?

    // MARK: - Services
    private let keychain: KeychainService
    private let orgListStore: OrgListStore
    private var pollTimer: Timer?
    public var pollInterval: TimeInterval = 300 // 5 minutes

    public init(
        keychain: KeychainService = KeychainService(),
        orgListStore: OrgListStore = UserDefaultsOrgListStore()
    ) {
        self.keychain = keychain
        self.orgListStore = orgListStore
        self.organizations = orgListStore.load()  // triggers didSet, harmless idempotent save
        loadCredentials()
        if isAuthenticated {
            // Defer polling start to next run loop to avoid publishing changes during init
            Task { @MainActor [weak self] in
                self?.startPolling()
            }
        }
    }

    // MARK: - Computed Display Values

    public var menuBarText: String {
        guard let usage else { return "—%" }
        let pct = Int((usage.fiveHour?.utilization ?? usage.sevenDay.utilization) * 100)
        return "\(pct)%"
    }

    public var menuBarUtilization: Double {
        usage?.fiveHour?.utilization ?? usage?.sevenDay.utilization ?? 0
    }

    public var usageColor: UsageColor {
        UsageColor.forUtilization(menuBarUtilization)
    }

    // MARK: - Lifecycle

    // Store both values in a single keychain item to avoid multiple password prompts on launch
    private static let credentialsAccount = "credentials"
    private static let credentialsSeparator: Character = "\0"

    public func loadCredentials() {
        guard let stored = try? keychain.retrieve(account: Self.credentialsAccount) else { return }
        let parts = stored.split(separator: Self.credentialsSeparator, maxSplits: 1)
        guard parts.count == 2 else { return }
        sessionKey = String(parts[0])
        orgId = String(parts[1])
    }

    public func saveCredentials(sessionKey: String, orgId: String) throws {
        let combined = "\(sessionKey)\(Self.credentialsSeparator)\(orgId)"
        try keychain.save(account: Self.credentialsAccount, value: combined)
        self.sessionKey = sessionKey
        self.orgId = orgId
    }

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

    /// Non-destructive recovery: wipes sessionKey + usage but preserves
    /// orgId and cached organizations so the reconnect screen can name the org.
    func handleSessionExpired() {
        try? keychain.delete(account: Self.credentialsAccount)
        sessionKey = nil
        usage = nil
        organizationDetails = nil
        error = .sessionExpired
        // orgId and organizations: preserved
    }

    // MARK: - API Calls

    public func validateAndFetchOrgs(sessionKey: String) async {
        isLoading = true
        error = nil
        self.sessionKey = sessionKey
        do {
            organizations = try await ClaudeAPIClient.fetchOrganizations(sessionKey: sessionKey)
            if organizations.count == 1 {
                try saveCredentials(sessionKey: sessionKey, orgId: organizations[0].uuid)
                startPolling()
            }
        } catch let apiError as APIError {
            error = .api(apiError)
            self.sessionKey = nil
        } catch {
            self.error = .network(error.localizedDescription)
            self.sessionKey = nil
        }
        isLoading = false
    }

    /// Switch to a different organization while keeping the current sessionKey.
    /// Clears stale usage/tier data (tier may differ between orgs) and triggers
    /// a fresh fetch via startPolling().
    public func switchOrganization(to org: Organization) async {
        guard let sessionKey else { return }
        do {
            try saveCredentials(sessionKey: sessionKey, orgId: org.uuid)
            usage = nil
            organizationDetails = nil
            error = nil
            startPolling()
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

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
    func applyKeyUpdateResult(newSessionKey: String, fetchedOrgs: [Organization]) {
        if let currentOrgId = orgId, fetchedOrgs.contains(where: { $0.uuid == currentOrgId }) {
            // Common case: cookie rotated, account/org unchanged
            do {
                try saveCredentials(sessionKey: newSessionKey, orgId: currentOrgId)
                organizations = fetchedOrgs
                pendingOrgPick = false
                pendingSessionKey = nil
                pendingOrganizations = []
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
        } catch APIError.sessionExpired {
            handleSessionExpired()
        } catch APIError.rateLimited {
            error = .rateLimited
        } catch {
            self.error = .network(error.localizedDescription)
        }
        isLoading = false
    }

    /// Replace the cached org list with a fresh server response.
    /// Empty responses are ignored to avoid wiping the cache on a transient blip.
    public func applyRefreshedOrgList(_ fetched: [Organization]) {
        guard !fetched.isEmpty else { return }
        organizations = fetched
    }

    // MARK: - Polling

    public func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refreshUsage() }
        }
        // Also fetch immediately
        Task { await refreshUsage() }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Update Check

    public func checkForUpdate() async {
        availableUpdate = await UpdateChecker.checkForUpdate()
    }
}

public enum AppError: Equatable {
    case api(APIError)
    case sessionExpired
    case rateLimited
    case network(String)

    public var message: String {
        switch self {
        case .sessionExpired: return String(localized: "error.sessionExpired", bundle: .module)
        case .rateLimited: return String(localized: "error.rateLimited", bundle: .module)
        case .api(let e): return String(localized: "error.api \(e.displayMessage)", bundle: .module)
        case .network(let msg): return msg
        }
    }
}
