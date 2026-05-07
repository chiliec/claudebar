import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    public let state: AppState

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

            // Session status
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(state.isAuthenticated ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(state.isAuthenticated
                             ? String(localized: "settings.connected", bundle: .module)
                             : String(localized: "settings.notConnected", bundle: .module))
                            .font(.subheadline)
                    }
                    Button {
                        state.signOut()
                    } label: {
                        Text("settings.updateSessionKey", bundle: .module)
                    }
                    .font(.subheadline)
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } label: {
                Text("settings.session", bundle: .module)
            }

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
        .frame(width: 320, height: 280)
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
