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
    /// Le `join()` amont attend un `JoinHandle` tokio, qui panique s'il est attendu de nouveau une
    /// fois terminé : il n'est appelé qu'une fois, et son issue est rendue à toutes les attentes.
    private let joinState = Mutex(JoinState.idle)

    private enum JoinState {
        case idle
        /// Le premier appelant attend l'amont ; les suivants attendent ici.
        case joining([CheckedContinuation<Void, any Error>])
        /// Issue de l'unique `join()` amont, erreur déjà traduite.
        case finished(Result<Void, MatrixError>)
    }

    private enum JoinRole {
        case leader
        case follower
        case finished(Result<Void, MatrixError>)
    }

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
            try await joinOnce()
        } catch {
            if cancelled.withLock({ $0 }) { throw CancellationError() }
            throw error
        }
        // L'amont rend la main sans erreur quand l'envoi est annulé : l'annulation prime.
        if cancelled.withLock({ $0 }) { throw CancellationError() }
    }

    private func joinOnce() async throws {
        let role: JoinRole = joinState.withLock { state in
            switch state {
            case .idle:
                state = .joining([])
                return .leader
            case .joining:
                return .follower
            case let .finished(result):
                return .finished(result)
            }
        }
        switch role {
        case let .finished(result):
            try result.get()
        case .follower:
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // L'issue peut être tombée entre la lecture du rôle et l'inscription.
                let result: Result<Void, MatrixError>? = joinState.withLock { state in
                    switch state {
                    case var .joining(waiters):
                        waiters.append(continuation)
                        state = .joining(waiters)
                        return nil
                    case let .finished(result):
                        return result
                    case .idle:
                        preconditionFailure("RustAttachmentUpload: follower without a leader")
                    }
                }
                if let result { continuation.resume(with: result.mapError { $0 }) }
            }
        case .leader:
            let result: Result<Void, MatrixError>
            do {
                try await handle.join()
                result = .success(())
            } catch {
                result = .failure(ErrorMapper.map(error))
            }
            let waiters: [CheckedContinuation<Void, any Error>] = joinState.withLock { state in
                defer { state = .finished(result) }
                guard case let .joining(waiters) = state else { return [] }
                return waiters
            }
            for waiter in waiters { waiter.resume(with: result.mapError { $0 }) }
            try result.get()
        }
    }
}
