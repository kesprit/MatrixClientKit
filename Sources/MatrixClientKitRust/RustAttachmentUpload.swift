import Synchronization
import MatrixClientKitCore

/// Implémentation de ``AttachmentUpload`` adossée au handle de tâche d'envoi du SDK Rust.
final class RustAttachmentUpload: AttachmentUpload {
    private let lifetime: ClientLifetime
    /// Retient la tâche d'envoi, donc le client interne : libéré par ``deinit`` à travers
    /// ``lifetime``, client encore vivant. Écrit seulement par l'initialiseur et par ``deinit``,
    /// d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var handleStorage: (any JoinHandleDriving)?
    private let cancelled = Mutex(false)

    init(handle: any JoinHandleDriving, lifetime: ClientLifetime) {
        self.handleStorage = handle
        self.lifetime = lifetime
    }

    deinit {
        lifetime.release(&handleStorage)
    }

    private var handle: any JoinHandleDriving {
        guard let handleStorage else {
            // Inatteignable : `handleStorage` n'est vidé que par `deinit`.
            preconditionFailure("RustAttachmentUpload used after deinitialization")
        }
        return handleStorage
    }

    func cancel() {
        // Le drapeau est posé sous verrou ; l'appel amont a lieu hors du verrou, une seule fois.
        let first = cancelled.withLock { flag in
            defer { flag = true }
            return !flag
        }
        if first { handle.cancel() }
    }

    func waitUntilQueued() async throws {
        if cancelled.withLock({ $0 }) { throw CancellationError() }
        do {
            try await handle.join()
        } catch {
            if cancelled.withLock({ $0 }) { throw CancellationError() }
            throw ErrorMapper.map(error)
        }
        // L'amont rend la main sans erreur quand l'envoi est annulé : l'annulation prime.
        if cancelled.withLock({ $0 }) { throw CancellationError() }
    }
}
