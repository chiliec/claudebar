import SwiftUI
import ClaudeBarUI

@main
struct ClaudeBarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(state: appState)
                .sheet(isPresented: $appState.showingSettings) {
                    SettingsView(state: appState)
                }
                .task {
                    appState.loadCredentials()
                    if appState.isAuthenticated {
                        appState.startPolling()
                    }
                    await appState.checkForUpdate()
                }
        } label: {
            HStack(spacing: 4) {
                RingProgressView(
                    progress: appState.menuBarUtilization,
                    color: appState.usageColor.swiftUIColor
                )
                Text(appState.menuBarText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(appState.error == .sessionExpired
                        ? Color.gray
                        : appState.usageColor.swiftUIColor)
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
