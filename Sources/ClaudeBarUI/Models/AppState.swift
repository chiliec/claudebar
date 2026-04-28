import SwiftUI

@MainActor
@Observable
public final class AppState {
    // MARK: - Auth State
    public var sessionKey: String?
    public var orgId: String?
    public var organizations: [Organization] = []
    public var isAuthenticated: Bool { sessionKey != nil && orgId != nil }

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
    private var pollTimer: Timer?
    public var pollInterval: TimeInterval = 300 // 5 minutes

    public init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
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

    public func clearCredentials() {
        try? keychain.delete(account: Self.credentialsAccount)
        sessionKey = nil
        orgId = nil
        usage = nil
        organizationDetails = nil
        organizations = []
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

    public func selectOrganization(_ org: Organization) async {
        guard let sessionKey else { return }
        do {
            try saveCredentials(sessionKey: sessionKey, orgId: org.uuid)
            startPolling()
        } catch {
            self.error = .network(error.localizedDescription)
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
        } catch APIError.sessionExpired {
            error = .sessionExpired
            clearCredentials()
        } catch APIError.rateLimited {
            error = .rateLimited
        } catch {
            self.error = .network(error.localizedDescription)
        }
        isLoading = false
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
