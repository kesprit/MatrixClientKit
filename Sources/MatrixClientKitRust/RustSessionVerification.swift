import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``SessionVerification`` adossée au `SessionVerificationController` amont.
public final class RustSessionVerification: SessionVerification {
    private let ownUserID: UserID
    private let loadController: @Sendable () async throws -> any VerificationControllerDriving
    private let broadcaster: StateBroadcaster<SessionVerificationState>
    private let controller = Mutex<(any VerificationControllerDriving)?>(nil)

    /// Retenu pour la durée de la session : le contrôleur amont ne documente pas qu'il garde son
    /// delegate en vie, et un delegate libéré ferait perdre en silence toute demande entrante.
    private let delegate: VerificationDelegateAdapter

    init(
        ownUserID: UserID,
        loadController: @escaping @Sendable () async throws -> any VerificationControllerDriving
    ) {
        self.ownUserID = ownUserID
        self.loadController = loadController
        let broadcaster = StateBroadcaster<SessionVerificationState>(.idle)
        self.broadcaster = broadcaster
        self.delegate = VerificationDelegateAdapter(ownUserID: ownUserID) { event in
            broadcaster.update { SessionVerificationReducer.reduce($0, event) }
        }
    }

    public var state: AsyncStream<SessionVerificationState> {
        broadcaster.stream()
    }

    var hasController: Bool {
        controller.withLock { $0 != nil }
    }

    /// Obtient le contrôleur amont et y pose le delegate, une seule fois.
    ///
    /// L'amont exige l'identité cross-signing de l'utilisateur dans le store local : avant la
    /// première sync, l'appel peut échouer. Il est alors retenté par l'appelant — à chaque commande
    /// et à chaque changement de l'état de vérification de l'appareil (spec 0.2, §6.2).
    @discardableResult
    func ensureController() async throws -> any VerificationControllerDriving {
        if let existing = controller.withLock({ $0 }) {
            return existing
        }

        let loaded = try await loadController()
        let (winner, isNew) = controller.withLock { current -> (any VerificationControllerDriving, Bool) in
            if let current { return (current, false) }
            current = loaded
            return (loaded, true)
        }

        // Hors verrou : on n'appelle jamais de code amont en tenant un verrou.
        if isNew {
            winner.setDelegate(delegate: delegate)
        }
        return winner
    }

    public func requestVerification() async throws {
        try await perform(.requestVerification, onSuccess: .requestSent) { controller, _ in
            try await controller.requestDeviceVerification()
        }
    }

    public func accept() async throws {
        let ownUserID = ownUserID
        // Pas d'événement local : `ready` n'est atteint que sur `didAcceptVerificationRequest`.
        try await perform(.accept, onSuccess: nil) { controller, state in
            guard case let .incomingRequest(request) = state else { return }
            try await controller.acknowledgeVerificationRequest(senderId: ownUserID.rawValue, flowId: request.id)
            try await controller.acceptVerificationRequest()
        }
    }

    public func startSAS() async throws {
        try await perform(.startSAS, onSuccess: .startSASSent) { controller, _ in
            try await controller.startSasVerification()
        }
    }

    public func approve() async throws {
        try await perform(.approve, onSuccess: .approvalSent) { controller, _ in
            try await controller.approveVerification()
        }
    }

    public func decline() async throws {
        // L'issue (`cancelled` ou `failed`) est signalée par l'amont.
        try await perform(.decline, onSuccess: nil) { controller, _ in
            try await controller.declineVerification()
        }
    }

    public func cancel() async throws {
        let ownUserID = ownUserID
        try await perform(.cancel, onSuccess: .cancelSent) { controller, state in
            // Une demande entrante n'est pas encore le flux actif du contrôleur : il faut la
            // désigner avant de pouvoir l'annuler.
            if case let .incomingRequest(request) = state {
                try await controller.acknowledgeVerificationRequest(senderId: ownUserID.rawValue, flowId: request.id)
            }
            try await controller.cancelVerification()
        }
    }

    /// Valide la commande contre l'état courant, l'exécute, puis applique l'événement de succès.
    private func perform(
        _ command: VerificationCommand,
        onSuccess event: VerificationEvent?,
        _ body: (any VerificationControllerDriving, SessionVerificationState) async throws -> Void
    ) async throws {
        let current = broadcaster.value
        guard SessionVerificationReducer.isAllowed(command, in: current) else {
            throw MatrixError.unexpected(
                message: "\(command.rawValue)() is not allowed while verification is \(current).",
                details: nil
            )
        }

        do {
            let controller = try await ensureController()
            try await body(controller, current)
        } catch {
            throw ErrorMapper.map(error)
        }

        if let event {
            broadcaster.update { SessionVerificationReducer.reduce($0, event) }
        }
    }
}

/// Delegate amont : traduit chaque callback en ``VerificationEvent``, de façon synchrone.
final class VerificationDelegateAdapter: SessionVerificationControllerDelegate {
    private let ownUserID: UserID
    private let handle: @Sendable (VerificationEvent) -> Void

    init(ownUserID: UserID, handle: @escaping @Sendable (VerificationEvent) -> Void) {
        self.ownUserID = ownUserID
        self.handle = handle
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
        // Le périmètre 0.2 est la vérification de ses propres appareils : une demande venue d'un
        // autre utilisateur n'a pas d'état public pour la représenter.
        guard details.senderProfile.userId == ownUserID.rawValue,
            let request = VerificationMapper.request(from: details)
        else { return }
        handle(.receivedRequest(request))
    }

    func didAcceptVerificationRequest() { handle(.otherDeviceAccepted) }
    func didStartSasVerification() { handle(.sasStarted) }

    func didReceiveVerificationData(data: SessionVerificationData) {
        handle(.receivedSASData(VerificationMapper.sasData(from: data)))
    }

    func didFail() { handle(.failed) }
    func didCancel() { handle(.cancelled) }
    func didFinish() { handle(.finished) }
}
