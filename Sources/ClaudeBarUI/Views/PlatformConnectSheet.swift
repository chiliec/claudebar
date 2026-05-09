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
