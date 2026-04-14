import Testing
@testable import ClaudeBarUI

@MainActor
@Suite(.serialized)
struct AppStateTests {
    private func makeState() -> AppState {
        let state = AppState(keychain: KeychainService(serviceName: "com.claudebar.test"))
        // Clean slate
        state.clearCredentials()
        return state
    }

    // MARK: - Authentication State

    @Test func initialStateIsNotAuthenticated() {
        let state = makeState()
        #expect(!state.isAuthenticated)
        #expect(state.sessionKey == nil)
        #expect(state.orgId == nil)
    }

    @Test func isAuthenticatedRequiresBothKeys() {
        let state = makeState()

        state.sessionKey = "sk-test"
        #expect(!state.isAuthenticated, "Should not be authenticated with only sessionKey")

        state.orgId = "org-123"
        #expect(state.isAuthenticated, "Should be authenticated with both keys")
    }

    @Test func saveAndLoadCredentials() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-ant-test", orgId: "org-abc")

        #expect(state.sessionKey == "sk-ant-test")
        #expect(state.orgId == "org-abc")
        #expect(state.isAuthenticated)

        // Create a new state with the same keychain to verify persistence
        let state2 = AppState(keychain: KeychainService(serviceName: "com.claudebar.test"))
        state2.loadCredentials()
        #expect(state2.sessionKey == "sk-ant-test")
        #expect(state2.orgId == "org-abc")
        #expect(state2.isAuthenticated)

        // Cleanup
        state2.clearCredentials()
    }

    @Test func clearCredentialsResetsState() throws {
        let state = makeState()
        try state.saveCredentials(sessionKey: "sk-test", orgId: "org-123")
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        state.organizations = [Organization(uuid: "org-123", name: "Test", capabilities: nil)]

        state.clearCredentials()

        #expect(state.sessionKey == nil)
        #expect(state.orgId == nil)
        #expect(state.usage == nil)
        #expect(state.organizations.isEmpty)
        #expect(!state.isAuthenticated)
    }

    // MARK: - Menu Bar Display Values

    @Test func menuBarTextWithNoUsage() {
        let state = makeState()
        #expect(state.menuBarText == "—%")
    }

    @Test func menuBarTextWithFiveHourUsage() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.73, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.menuBarText == "73%")
    }

    @Test func menuBarTextFallsBackToSevenDay() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: nil,
            sevenDay: WindowUsage(utilization: 0.42, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.menuBarText == "42%")
    }

    @Test func menuBarTextAtZero() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.0, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.0, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.menuBarText == "0%")
    }

    @Test func menuBarTextAtFull() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 1.0, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.menuBarText == "100%")
    }

    // MARK: - Utilization & Color

    @Test func menuBarUtilizationWithNoUsage() {
        let state = makeState()
        #expect(state.menuBarUtilization == 0)
    }

    @Test func menuBarUtilizationPrefersFiveHour() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.8, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.2, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.menuBarUtilization == 0.8)
    }

    @Test func usageColorGreen() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.1, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.usageColor == .green)
    }

    @Test func usageColorYellow() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.6, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.1, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.usageColor == .yellow)
    }

    @Test func usageColorOrange() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.85, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.1, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.usageColor == .orange)
    }

    @Test func usageColorRed() {
        let state = makeState()
        state.usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.95, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.1, resetsAt: nil),
            sevenDaySonnet: nil, sevenDayOpus: nil, extraUsage: nil
        )
        #expect(state.usageColor == .red)
    }

    // MARK: - Error Messages

    @Test func appErrorMessages() {
        #expect(AppError.sessionExpired.message == "Session expired — update your key")
        #expect(AppError.rateLimited.message == "Rate limited — will retry")
        #expect(AppError.network("Connection failed").message == "Connection failed")
        #expect(AppError.api(.httpError(500)).message == "API error: httpError(500)")
    }

    // MARK: - Organization Selection

    @Test func sessionKeyRetainedForOrgSelection() {
        let state = makeState()
        state.sessionKey = "sk-ant-multi-org"
        state.organizations = [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
            Organization(uuid: "org-2", name: "Work", capabilities: nil),
        ]

        #expect(state.sessionKey == "sk-ant-multi-org")
        #expect(!state.isAuthenticated, "Not yet authenticated until org is selected")
    }

    @Test func selectOrganizationSavesCredentials() throws {
        let state = makeState()
        state.sessionKey = "sk-ant-test"

        try state.saveCredentials(sessionKey: "sk-ant-test", orgId: "org-2")

        #expect(state.sessionKey == "sk-ant-test")
        #expect(state.orgId == "org-2")
        #expect(state.isAuthenticated)

        state.clearCredentials()
    }

    // MARK: - Initial UI State

    @Test func initialLoadingState() {
        let state = makeState()
        #expect(!state.isLoading)
        #expect(state.error == nil)
        #expect(state.lastUpdated == nil)
        #expect(!state.showingSettings)
    }
}
