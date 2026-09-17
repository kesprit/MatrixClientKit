/// Ce qui fait évoluer un flux de vérification : un callback du contrôleur amont, ou le succès
/// d'une commande locale.
package enum VerificationEvent: Sendable, Hashable {
    // Callbacks amont (`SessionVerificationControllerDelegate`).
    case receivedRequest(VerificationRequest)
    case otherDeviceAccepted
    case sasStarted
    case receivedSASData(SASData)
    case finished
    case cancelled
    case failed

    // Succès de commandes locales.
    case requestSent
    case startSASSent
    case approvalSent
    case cancelSent
}

/// Les commandes publiques de ``SessionVerification``, pour la validation d'état.
package enum VerificationCommand: String, Sendable, Hashable {
    case requestVerification
    case accept
    case startSAS
    case approve
    case decline
    case cancel
}

/// Machine à états de la vérification de session (spec 0.2, §6.1).
///
/// Fonction pure : elle ne sait rien du SDK, ce qui permet d'en tester chaque transition sans
/// binaire. Un événement incohérent avec l'état courant laisse l'état inchangé — l'amont peut
/// livrer un callback tardif, qui ne doit jamais ranimer un flux terminé.
package enum SessionVerificationReducer {

    package static func reduce(
        _ state: SessionVerificationState,
        _ event: VerificationEvent
    ) -> SessionVerificationState {
        switch event {
        case let .receivedRequest(request):
            return canStartNewFlow(state) ? .incomingRequest(request) : state
        case .requestSent:
            return canStartNewFlow(state) ? .waitingForOtherDevice : state
        case .otherDeviceAccepted:
            switch state {
            case .waitingForOtherDevice, .incomingRequest: return .ready
            default: return state
            }
        case .sasStarted, .startSASSent:
            switch state {
            case .ready, .startingSAS: return .startingSAS
            default: return state
            }
        case let .receivedSASData(data):
            switch state {
            case .ready, .startingSAS, .comparing: return .comparing(data)
            default: return state
            }
        case .approvalSent:
            if case .comparing = state { return .confirming }
            return state
        case .finished:
            switch state {
            case .comparing, .confirming: return .verified
            default: return state
            }
        case .cancelled, .cancelSent:
            return isInFlight(state) ? .cancelled : state
        case .failed:
            return isInFlight(state) ? .failed : state
        }
    }

    package static func isAllowed(_ command: VerificationCommand, in state: SessionVerificationState)
        -> Bool
    {
        switch command {
        case .requestVerification:
            return canStartNewFlow(state)
        case .accept:
            if case .incomingRequest = state { return true }
            return false
        case .startSAS:
            return state == .ready
        case .approve, .decline:
            if case .comparing = state { return true }
            return false
        case .cancel:
            return isInFlight(state)
        }
    }

    private static func canStartNewFlow(_ state: SessionVerificationState) -> Bool {
        state == .idle || state.isFinished
    }

    private static func isInFlight(_ state: SessionVerificationState) -> Bool {
        state != .idle && !state.isFinished
    }
}
