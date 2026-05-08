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
            titleColor: .orange,
            submitAction: { [state] key in await state.updateSessionKey(key) }
        )
    }

    private var titleString: String {
        if let orgId = state.orgId,
           let name = state.organizations.first(where: { $0.uuid == orgId })?.displayName {
            return String(localized: "session.reconnect \(name)", bundle: .module)
        }
        return String(localized: "session.expired", bundle: .module)
    }
}
