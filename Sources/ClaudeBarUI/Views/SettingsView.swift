import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    public let state: AppState

    public init(state: AppState) { self.state = state }
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .font(.caption)
            }

            // Session status
            GroupBox("Session") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(state.isAuthenticated ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(state.isAuthenticated ? "Connected" : "Not connected")
                            .font(.caption)
                    }
                    Button("Update Session Key") {
                        state.clearCredentials()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // Launch at login
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 8) {
                    LaunchAtLoginToggle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Spacer()

            Button("Quit ClaudeBar") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(16)
        .frame(width: 320, height: 280)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .font(.caption)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = !newValue // revert on failure
                }
            }
    }
}

#Preview("Settings - Connected") {
    let state = AppState(keychain: KeychainService(serviceName: "com.claudebar.preview"))
    state.sessionKey = "fake-key"
    state.orgId = "fake-org"
    return SettingsView(state: state)
}

#Preview("Settings - Disconnected") {
    SettingsView(state: AppState(keychain: KeychainService(serviceName: "com.claudebar.preview")))
}
