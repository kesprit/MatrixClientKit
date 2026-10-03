/// Machine à états de la connexion par QR (spec 0.4, §4.4).
///
/// Fonction pure, sur le modèle de ``SessionVerificationReducer`` : un événement incohérent avec
/// l'état courant le laisse inchangé, et un état terminal absorbe tout — l'amont peut livrer un
/// progrès tardif après une annulation, qui ne doit jamais ranimer le flux.
package enum QRCodeLoginReducer {

    package static func reduce(_ state: QRCodeLoginState, _ event: QRCodeLoginEvent) -> QRCodeLoginState {
        guard !state.isFinished else { return state }

        switch event {
        case let .failed(failure):
            return .failed(failure)
        case let .qrReady(data):
            return state == .starting ? .displayQRCode(data) : state
        case .qrScanned:
            if case .displayQRCode = state { return .enterCheckCode }
            return state
        case let .secureChannelEstablished(code):
            return state == .starting ? .displayCheckCode(code) : state
        case let .waitingForToken(userCode):
            switch state {
            case .enterCheckCode, .displayCheckCode, .waitingForApproval: return .waitingForApproval(userCode: userCode)
            default: return state
            }
        case .syncingSecrets:
            if case .waitingForApproval = state { return .syncingSecrets }
            return state
        case .done:
            switch state {
            case .waitingForApproval, .syncingSecrets: return .done
            default: return state
            }
        }
    }

    package static func canSubmitCheckCode(in state: QRCodeLoginState) -> Bool {
        state == .enterCheckCode
    }
}
