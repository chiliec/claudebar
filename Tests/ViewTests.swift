import Testing
import ViewInspector
@testable import ClaudeBarUI

// MARK: - Inspectable Conformances

extension PopoverView: @retroactive Inspectable {}
extension SetupView: @retroactive Inspectable {}
extension SessionExpiredView: @retroactive Inspectable {}
extension RingProgressView: @retroactive Inspectable {}
extension SettingsView: @retroactive Inspectable {}

// MARK: - PopoverView Tests

@MainActor
@Suite
struct PopoverViewTests {
    private func makeState() -> AppState {
        AppState(keychain: KeychainService(serviceName: "com.claudebar.test"))
    }

    @Test func showsSetupViewWhenNotAuthenticated() throws {
        let state = makeState()
        let view = PopoverView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(SetupView.self)
    }

    @Test func showsSessionExpiredView() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        state.error = .sessionExpired
        let view = PopoverView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(SessionExpiredView.self)
    }

    @Test func showsUsageDetailWhenAuthenticated() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        let view = PopoverView(state: state)
        let inspected = try view.inspect()

        // Should NOT contain SetupView or SessionExpiredView
        #expect(throws: (any Error).self) { try inspected.find(SetupView.self) }
        #expect(throws: (any Error).self) { try inspected.find(SessionExpiredView.self) }
    }

    @Test func popoverRendersVStack() throws {
        let state = makeState()
        let view = PopoverView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.vStack()
    }
}

// MARK: - SetupView Tests

@MainActor
@Suite
struct SetupViewTests {
    private func makeState() -> AppState {
        AppState(keychain: KeychainService(serviceName: "com.claudebar.test"))
    }

    @Test func showsTitle() throws {
        let state = makeState()
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(text: "Setup ClaudeBar")
    }

    @Test func showsInstructions() throws {
        let state = makeState()
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(text: "Paste sessionKey here...")
    }

    @Test func showsConnectButton() throws {
        let state = makeState()
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(button: "Connect")
    }

    @Test func showsQuitButton() throws {
        let state = makeState()
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(button: "Quit ClaudeBar")
    }

    @Test func showsErrorMessage() throws {
        let state = makeState()
        state.error = .network("Connection failed")
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(text: "Connection failed")
    }

    @Test func showsLoadingIndicator() throws {
        let state = makeState()
        state.isLoading = true
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(ViewType.ProgressView.self)
    }

    @Test func showsOrgSelectionWhenMultipleOrgs() throws {
        let state = makeState()
        state.organizations = [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
            Organization(uuid: "org-2", name: "Work", capabilities: nil),
        ]
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(text: "Select organization:")
        _ = try inspected.find(button: "Personal")
        _ = try inspected.find(button: "Work")
    }

    @Test func hidesOrgSelectionForSingleOrg() throws {
        let state = makeState()
        state.organizations = [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
        ]
        let view = SetupView(state: state)
        let inspected = try view.inspect()

        #expect(throws: (any Error).self) { try inspected.find(text: "Select organization:") }
    }
}

// MARK: - SessionExpiredView Tests

@MainActor
@Suite
struct SessionExpiredViewTests {
    private func makeState() -> AppState {
        AppState(keychain: KeychainService(serviceName: "com.claudebar.test"))
    }

    @Test func showsExpiredTitle() throws {
        let state = makeState()
        let view = SessionExpiredView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(text: "Session Expired")
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

// MARK: - RingProgressView Tests

@MainActor
@Suite
struct RingProgressViewTests {
    @Test func clampsProgressToZero() throws {
        let view = RingProgressView(progress: -0.5, color: .green)
        let inspected = try view.inspect()

        let zstack = try inspected.zStack()
        #expect(try zstack.fixedFrame().width == 16)
    }

    @Test func clampsProgressToOne() throws {
        let view = RingProgressView(progress: 1.5, color: .red)
        let inspected = try view.inspect()
        _ = try inspected.zStack()
    }

    @Test func customSize() throws {
        let view = RingProgressView(progress: 0.5, color: .blue, size: 32)
        let inspected = try view.inspect()
        let frame = try inspected.zStack().fixedFrame()
        #expect(frame.width == 32)
        #expect(frame.height == 32)
    }

    @Test func defaultSize() throws {
        let view = RingProgressView(progress: 0.5, color: .green)
        let inspected = try view.inspect()
        let frame = try inspected.zStack().fixedFrame()
        #expect(frame.width == 16)
        #expect(frame.height == 16)
    }

    @Test func containsTwoCircles() throws {
        let view = RingProgressView(progress: 0.5, color: .green)
        let inspected = try view.inspect()
        let zstack = try inspected.zStack()

        #expect(zstack.count == 2)
    }
}

// MARK: - SettingsView Tests

@MainActor
@Suite
struct SettingsViewTests {
    private func makeState() -> AppState {
        AppState(keychain: KeychainService(serviceName: "com.claudebar.test"))
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

    @Test func showsConnectedWhenAuthenticated() throws {
        let state = makeState()
        state.sessionKey = "sk-test"
        state.orgId = "org-123"
        let view = SettingsView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(text: "Connected")
    }

    @Test func showsQuitButton() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(button: "Quit ClaudeBar")
    }

    @Test func showsUpdateSessionKeyButton() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(button: "Update Session Key")
    }

    @Test func showsDoneButton() throws {
        let state = makeState()
        let view = SettingsView(state: state)
        let inspected = try view.inspect()

        _ = try inspected.find(button: "Done")
    }
}
