import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Phases d'une connexion par QR, séparées du flux pour être testées sans FFI.
///
/// Arbitre la course entre ``cancel()`` et la construction de la session : une fois
/// ``commit()`` accordé, l'annulation est sans effet, et `start()` rend la session. Sans cela,
/// une annulation pendant ``LoginAttempt/succeed(expecting:)`` laisserait l'état à
/// `.failed(.cancelled)` alors qu'une session est persistée.
final class QRCodeLoginGate<Run: Sendable>: Sendable {
    private enum Phase {
        case idle
        case running(Run)
        case committing
        case cancelled
    }

    enum Refusal: Error, Equatable {
        case alreadyStarted
        case cancelled
    }

    enum CancelOutcome {
        /// La session est déjà en construction : l'annulation est sans effet.
        case refused
        /// Annulé ; `run` est le déroulé à interrompre, s'il a commencé.
        case cancelled(run: Run?)
    }

    private let phase = Mutex(Phase.idle)

    /// Lance le déroulé sous le verrou : une annulation concurrente le trouve, ou l'empêche.
    func start(_ launch: () -> Run) throws(Refusal) -> Run {
        try phase.withLock { phase throws(Refusal) in
            switch phase {
            case .idle:
                let run = launch()
                phase = .running(run)
                return run
            case .cancelled: throw .cancelled
            case .running, .committing: throw .alreadyStarted
            }
        }
    }

    func cancel() -> CancelOutcome {
        phase.withLock { phase in
            switch phase {
            case .committing: return .refused
            case let .running(run):
                phase = .cancelled
                return .cancelled(run: run)
            case .idle, .cancelled:
                phase = .cancelled
                return .cancelled(run: nil)
            }
        }
    }

    /// Passe à la construction de la session. `false` si la connexion a été annulée.
    func commit() -> Bool {
        phase.withLock { phase in
            guard case .running = phase else { return false }
            phase = .committing
            return true
        }
    }

    var isCancelled: Bool {
        phase.withLock { phase in
            if case .cancelled = phase { return true }
            return false
        }
    }
}

/// Implémentation de ``QRCodeLogin`` (spec 0.4, §4.4).
final class RustQRCodeLogin: QRCodeLogin {
    enum Mode: Sendable {
        /// Ce nouvel appareil affiche le QR.
        case display(ClientTarget)
        /// Ce nouvel appareil a scanné le QR d'un appareil connecté.
        case scanned(Data)
    }

    typealias MakeClient = @Sendable (ClientTarget, LocalStore) async throws -> Client

    private let restorer: SessionRestorer
    private let configuration: MatrixClientKitCore.OAuthConfiguration
    private let mode: Mode
    private let makeClient: MakeClient
    private let broadcaster = StateBroadcaster<QRCodeLoginState>(.starting)
    private let checkCodeSender = Mutex<CheckCodeSender?>(nil)
    private let gate = QRCodeLoginGate<Task<RustMatrixSession, any Error>>()

    /// - Parameter makeClient: couture de test, comme pour
    ///   ``LoginAttempt/begin(restorer:target:reusing:makeClient:)``.
    init(
        restorer: SessionRestorer,
        configuration: MatrixClientKitCore.OAuthConfiguration,
        mode: Mode,
        makeClient: MakeClient? = nil
    ) {
        self.restorer = restorer
        self.configuration = configuration
        self.mode = mode
        self.makeClient =
            makeClient ?? { target, localStore in
                try await restorer.makeClient(target: target, localStore: localStore)
            }
    }

    var state: AsyncStream<QRCodeLoginState> { broadcaster.stream() }

    func start() async throws -> any MatrixSession {
        let task: Task<RustMatrixSession, any Error>
        do {
            task = try gate.start { Task { try await self.perform() } }
        } catch .alreadyStarted {
            throw MatrixError.unexpected(message: "This QR-code login has already been started.", details: nil)
        } catch .cancelled {
            // Annulé avant de démarrer : ni client ni store.
            throw CancellationError()
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            self.cancel()
        }
    }

    func submitCheckCode(_ code: UInt8) async throws {
        guard QRCodeLoginReducer.canSubmitCheckCode(in: broadcaster.value),
            let sender = checkCodeSender.withLock({ $0 })
        else {
            throw MatrixError.unexpected(message: "No check code is expected now.", details: nil)
        }
        do {
            try await sender.send(code: code)
        } catch {
            throw MatrixError.unexpected(
                message: "The check code could not be sent.", details: String(describing: error))
        }
    }

    func cancel() {
        guard case let .cancelled(run) = gate.cancel() else { return }
        apply(.failed(.cancelled))
        run?.cancel()
    }

    private func apply(_ event: QRCodeLoginEvent) {
        broadcaster.update { QRCodeLoginReducer.reduce($0, event) }
    }

    /// Progrès amont. `.done` n'est publié qu'une fois la session construite : l'état terminal
    /// absorbe tout, et un échec de ``LoginAttempt/succeed(expecting:)`` ne pourrait plus
    /// s'y inscrire.
    private func progress(_ event: QRCodeLoginEvent?) {
        guard let event, event != .done else { return }
        apply(event)
    }

    private func perform() async throws -> RustMatrixSession {
        let target: ClientTarget
        let scannedData: QrCodeData?
        switch mode {
        case let .display(displayTarget):
            target = displayTarget
            scannedData = nil
        case let .scanned(bytes):
            guard let scanned = QRCodeMapper.target(scanned: bytes) else {
                apply(.failed(.notSupported))
                throw MatrixError.unexpected(message: "This QR code is not a Matrix sign-in code.", details: nil)
            }
            target = scanned.target
            scannedData = scanned.data
        }

        let attempt: LoginAttempt
        do {
            attempt = try await LoginAttempt.begin(
                restorer: restorer, target: target, reusing: nil, makeClient: makeClient)
        } catch {
            if gate.isCancelled { throw CancellationError() }
            apply(.failed(.unknown))
            throw error
        }

        do {
            // Annulé pendant la construction du client : inutile d'ouvrir le canal.
            if gate.isCancelled { throw CancellationError() }
            try await exchange(on: attempt.client, scannedData: scannedData)
            // Les appels amont ignorent l'annulation Swift : on la constate à leur retour. Passé
            // ce point, `cancel()` est sans effet et la session sera rendue.
            guard gate.commit() else { throw CancellationError() }
            let session = try await attempt.succeed(expecting: nil)
            // Forcé, sans le réducteur : l'amont peut sauter une étape (`.syncingSecrets` sans
            // secrets à recevoir), et `.done` n'y serait pas accepté depuis tout état.
            broadcaster.update { _ in .done }
            return session
        } catch {
            attempt.fail()
            // Annulation locale, ou `HumanQrLoginError.Cancelled` amont : `.cancelled` lève
            // `CancellationError` dans les deux cas (spec 0.4, §4.4).
            let failure = gate.isCancelled || error is CancellationError ? .cancelled : QRCodeMapper.failure(error)
            apply(.failed(failure))
            if failure == .cancelled { throw CancellationError() }
            if let error = error as? MatrixError { throw error }
            throw MatrixError.unexpected(message: "QR-code login failed.", details: String(describing: error))
        }
    }

    /// Le canal QR amont, de bout en bout. Fonction à part pour borner la vie du handler : il
    /// retient, côté Rust, le client interne du SDK, et doit être libéré **avant** le `Client` de
    /// la tentative — le dernier `Arc<ClientInner>` libéré hors du runtime Tokio fait paniquer la
    /// fermeture des connexions SQLite (voir ``RustMatrixSession``, `Dependents`). Le handler
    /// meurt au retour de cette fonction ; l'appelant se sert encore de la tentative ensuite.
    private func exchange(on client: Client, scannedData: QrCodeData?) async throws {
        let handler = client.newLoginWithQrCodeHandler(oauthConfiguration: OAuthMapper.configuration(configuration))
        if let scannedData {
            try await handler.scan(
                qrCodeData: scannedData,
                progressListener: ScannedListener { [weak self] progress in
                    self?.progress(QRCodeMapper.event(progress))
                })
        } else {
            try await handler.generate(
                progressListener: GeneratedListener { [weak self] progress in
                    if case let .qrScanned(sender) = progress { self?.checkCodeSender.withLock { $0 = sender } }
                    self?.progress(QRCodeMapper.event(progress))
                })
        }
    }
}

private final class ScannedListener: QrLoginProgressListener {
    private let handler: @Sendable (QrLoginProgress) -> Void
    init(_ handler: @escaping @Sendable (QrLoginProgress) -> Void) { self.handler = handler }
    func onUpdate(state: QrLoginProgress) { handler(state) }
}

private final class GeneratedListener: GeneratedQrLoginProgressListener {
    private let handler: @Sendable (GeneratedQrLoginProgress) -> Void
    init(_ handler: @escaping @Sendable (GeneratedQrLoginProgress) -> Void) { self.handler = handler }
    func onUpdate(state: GeneratedQrLoginProgress) { handler(state) }
}
