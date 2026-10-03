import Foundation
import Synchronization
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``QRCodeLogin`` (spec 0.4, §4.4).
final class RustQRCodeLogin: QRCodeLogin {
    enum Mode: Sendable {
        /// Ce nouvel appareil affiche le QR.
        case display(ClientTarget)
        /// Ce nouvel appareil a scanné le QR d'un appareil connecté.
        case scanned(Data)
    }

    private let restorer: SessionRestorer
    private let configuration: MatrixClientKitCore.OAuthConfiguration
    private let mode: Mode
    private let broadcaster = StateBroadcaster<QRCodeLoginState>(.starting)
    private let checkCodeSender = Mutex<CheckCodeSender?>(nil)
    private let run = Mutex<Task<RustMatrixSession, any Error>?>(nil)

    init(restorer: SessionRestorer, configuration: MatrixClientKitCore.OAuthConfiguration, mode: Mode) {
        self.restorer = restorer
        self.configuration = configuration
        self.mode = mode
    }

    var state: AsyncStream<QRCodeLoginState> { broadcaster.stream() }

    func start() async throws -> any MatrixSession {
        let task: Task<RustMatrixSession, any Error> = try run.withLock { run in
            guard run == nil else {
                throw MatrixError.unexpected(message: "This QR-code login has already been started.", details: nil)
            }
            // `cancel()` pose l'état avant de lire `run` : annulé avant ce point, le flux ne
            // démarre pas — ni client ni store ; annulé après, il trouve la tâche à annuler.
            guard broadcaster.value != .failed(.cancelled) else { throw CancellationError() }
            let task = Task { try await self.perform() }
            run = task
            return task
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
        apply(.failed(.cancelled))
        run.withLock { $0 }?.cancel()
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

    private var isCancelled: Bool {
        Task.isCancelled || broadcaster.value == .failed(.cancelled)
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
            attempt = try await LoginAttempt.begin(restorer: restorer, target: target, reusing: nil)
        } catch {
            if isCancelled { throw CancellationError() }
            apply(.failed(.unknown))
            throw error
        }

        do {
            // Annulé pendant la construction du client : inutile d'ouvrir le canal.
            try Task.checkCancellation()
            let handler = attempt.client.newLoginWithQrCodeHandler(
                oauthConfiguration: OAuthMapper.configuration(configuration))
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
            // Les appels amont ignorent l'annulation Swift : on la constate à leur retour.
            try Task.checkCancellation()
            let session = try await attempt.succeed(expecting: nil)
            apply(.done)
            return session
        } catch {
            attempt.fail()
            // Annulation locale, ou `HumanQrLoginError.Cancelled` amont : `.cancelled` lève
            // `CancellationError` dans les deux cas (spec 0.4, §4.4).
            let failure = isCancelled || error is CancellationError ? .cancelled : QRCodeMapper.failure(error)
            apply(.failed(failure))
            if failure == .cancelled { throw CancellationError() }
            throw MatrixError.unexpected(message: "QR-code login failed.", details: String(describing: error))
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
