import MatrixClientKitCore

/// Implémentation de ``SendHandle`` adossée au handle d'envoi du SDK Rust.
final class RustSendHandle: SendHandle {
    private let lifetime: ClientLifetime?
    /// Retient la file d'envoi de la room, donc le client interne : libéré par ``deinit`` à
    /// travers ``lifetime``, client encore vivant. Écrit seulement par l'initialiseur et par
    /// ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var handleStorage: (any SendHandleDriving)?

    init(handle: any SendHandleDriving, lifetime: ClientLifetime?) {
        self.handleStorage = handle
        self.lifetime = lifetime
    }

    deinit {
        if let lifetime {
            lifetime.release(&handleStorage)
        } else {
            handleStorage = nil
        }
    }

    private var handle: any SendHandleDriving {
        guard let handleStorage else {
            // Inatteignable : `handleStorage` n'est vidé que par `deinit`.
            preconditionFailure("RustSendHandle used after deinitialization")
        }
        return handleStorage
    }

    @discardableResult
    func cancel() async throws -> Bool {
        do {
            return try await handle.abort(reason: nil)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    func retry() async throws {
        do {
            try await handle.tryResend()
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
