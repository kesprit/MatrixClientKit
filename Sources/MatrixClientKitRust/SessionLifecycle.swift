import Synchronization
import MatrixClientKitCore

/// Fin de vie d'une session : déconnexion demandée par l'application, ou imposée par le serveur.
///
/// Les deux chemins partagent une règle : arrêt de la sync et effacement local n'ont lieu qu'une
/// fois, et `.signedOut` n'est publié qu'**après** l'effacement — une application qui observe
/// `.signedOut` peut compter sur un disque déjà propre.
final class SessionLifecycle: Sendable {
    private let broadcaster = StateBroadcaster<AuthState>(.signedIn)
    private let terminationClaimed = Mutex(false)
    private let stopSync: @Sendable () async -> Void
    private let erase: @Sendable () throws -> Void

    init(
        stopSync: @escaping @Sendable () async -> Void,
        erase: @escaping @Sendable () throws -> Void
    ) {
        self.stopSync = stopSync
        self.erase = erase
    }

    var authState: AsyncStream<AuthState> {
        broadcaster.stream()
    }

    var current: AuthState {
        broadcaster.value
    }

    /// Réagit à `ClientDelegate.didReceiveAuthError(isSoftLogout:)`.
    ///
    /// Le callback amont est synchrone alors que l'arrêt de la sync est asynchrone : la
    /// terminaison part dans un `Task`, renvoyé pour que les tests puissent l'attendre. La
    /// revendication de terminaison, elle, est synchrone : un callback répété ne lance jamais une
    /// seconde purge.
    @discardableResult
    func handleAuthError(isSoftLogout: Bool) -> Task<Void, Never>? {
        if isSoftLogout {
            broadcaster.update { $0 == .signedIn ? .softLoggedOut : $0 }
            return nil
        }

        guard claimTermination() else { return nil }
        return Task {
            await self.stopSync()
            // Un effacement en échec est avalé : la session est morte côté serveur quoi qu'il
            // arrive, et la laisser en `.signedIn` promettrait une session qui n'existe plus.
            try? self.erase()
            self.broadcaster.update { _ in .signedOut }
        }
    }

    /// Déconnexion demandée par l'application.
    ///
    /// - Important: l'effacement local a lieu même si l'appel serveur échoue — un utilisateur qui
    ///   se déconnecte hors ligne ne doit pas rester connecté localement. L'erreur serveur remonte
    ///   ensuite, sauf `unknownToken` après un soft logout : le serveur a déjà refusé ce jeton, la
    ///   déconnexion a donc abouti.
    func logout(server: @Sendable () async throws -> Void) async throws {
        guard claimTermination() else { return }
        let wasSoftLoggedOut = current == .softLoggedOut

        await stopSync()

        do {
            try await server()
        } catch {
            try? erase()
            broadcaster.update { _ in .signedOut }

            let mapped = ErrorMapper.map(error)
            if wasSoftLoggedOut, case .authentication(.unknownToken) = mapped {
                return
            }
            throw mapped
        }

        defer { broadcaster.update { _ in .signedOut } }
        do {
            try erase()
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    private func claimTermination() -> Bool {
        terminationClaimed.withLock { claimed in
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
