import Synchronization
import MatrixClientKitCore

/// Fin de vie d'une session : déconnexion demandée par l'application, ou imposée par le serveur.
///
/// Les deux chemins partagent une règle : arrêt de la sync et effacement local n'ont lieu qu'une
/// fois, et `.signedOut` n'est publié qu'**après** l'effacement — une application qui observe
/// `.signedOut` peut compter sur un disque déjà propre.
final class SessionLifecycle: Sendable {
    private let broadcaster = StateBroadcaster<AuthState>(.signedIn)
    /// La tâche qui termine la session, une fois revendiquée par le premier appelant (hard
    /// logout ou `logout()`). Sert de rendez-vous : un appelant qui arrive pendant qu'une
    /// terminaison est déjà en cours l'attend au lieu de rejouer le travail, et la retrouve déjà
    /// terminée si la session est déjà `.signedOut`.
    private let termination = Mutex<Task<Void, Never>?>(nil)
    private let isReplaced = Mutex(false)
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
    /// seconde purge, et ne reçoit jamais la tâche de quelqu'un d'autre — seul le revendicateur la
    /// récupère, les autres reçoivent `nil` comme avant.
    @discardableResult
    func handleAuthError(isSoftLogout: Bool) -> Task<Void, Never>? {
        if isReplaced.withLock({ $0 }) { return nil }
        if isSoftLogout {
            broadcaster.update { $0 == .signedIn ? .softLoggedOut : $0 }
            return nil
        }

        let (isClaimant, task) = claimOrJoinTermination {
            Task {
                await self.stopSync()
                // Un effacement en échec est avalé : la session est morte côté serveur quoi qu'il
                // arrive, et la laisser en `.signedIn` promettrait une session qui n'existe plus.
                try? self.erase()
                self.broadcaster.update { _ in .signedOut }
            }
        }
        return isClaimant ? task : nil
    }

    /// Déconnexion demandée par l'application.
    ///
    /// - Important: l'effacement local a lieu même si l'appel serveur échoue — un utilisateur qui
    ///   se déconnecte hors ligne ne doit pas rester connecté localement. L'erreur serveur remonte
    ///   ensuite, sauf `unknownToken` après un soft logout : le serveur a déjà refusé ce jeton, la
    ///   déconnexion a donc abouti.
    ///
    /// - Note: si une terminaison est déjà en cours — un hard logout, ou un autre appel à
    ///   `logout()` — cet appel ne rejoue rien : il attend la fin de celle-ci puis ressort sans
    ///   erreur ni appel serveur. Rejouer le travail doublerait l'effacement, et rendre la main
    ///   avant la fin de l'autre terminaison exposerait un état encore périmé (`current` pas
    ///   encore `.signedOut`) à un appelant qui croirait la déconnexion terminée.
    func logout(server: @Sendable () async throws -> Void) async throws {
        if isReplaced.withLock({ $0 }) { return }
        // Un simple relais : `stream` ne porte aucune valeur, sa seule fin (`continuation.finish`
        // ci-dessous) signale que le travail réel — fait par le revendicateur, plus bas — est
        // terminé, qu'il ait réussi ou levé une erreur. Ce relais n'est jamais construit ni gardé
        // si quelqu'un d'autre a déjà revendiqué la terminaison.
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let (isClaimant, relay) = claimOrJoinTermination {
            Task {
                var iterator = stream.makeAsyncIterator()
                _ = await iterator.next()
            }
        }

        guard isClaimant else {
            // Perdant : la déconnexion a de toute façon abouti (ou est en train d'aboutir)
            // ailleurs, donc pas d'erreur à lever ici — seulement attendre qu'elle le soit
            // réellement avant de ressortir, pour ne jamais laisser croire à un appelant que
            // `current` reflète déjà `.signedOut` alors que l'effacement est encore en vol.
            await relay.value
            return
        }

        defer { continuation.finish() }

        await stopSync()

        do {
            try await server()
        } catch {
            // Lu ici, avant la publication de `.signedOut` : un soft logout survenu pendant
            // l'appel serveur rend lui aussi `unknownToken` attendu.
            let wasSoftLoggedOut = current == .softLoggedOut
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

    /// Garde de ``RustMatrixSession/reauthenticate(_:)`` : seule une session en soft logout se
    /// reconnecte sur le même appareil.
    func requireSoftLoggedOut() throws {
        guard current == .softLoggedOut, !isReplaced.withLock({ $0 }) else {
            throw MatrixError.unexpected(
                message: "Only a session the homeserver soft-logged out can sign in again.",
                details: "\(current)"
            )
        }
    }

    /// Arrête la sync avant de céder le store à une reconnexion.
    func stopSyncForReplacement() async {
        await stopSync()
    }

    /// La session a été remplacée par une reconnexion (spec 0.4, §5.5) : son store appartient
    /// désormais à la remplaçante. Plus rien ne l'efface — ni `logout()`, ni un hard logout
    /// tardif —, et elle publie `.signedOut`.
    func markReplaced() {
        isReplaced.withLock { $0 = true }
        broadcaster.update { _ in .signedOut }
    }

    /// Revendique la terminaison si elle ne l'est pas déjà, sous le même verrou que la lecture —
    /// pas de fenêtre où deux appelants se croient tous deux revendicateurs. Le premier à passer
    /// ici construit `task` (le travail réel pour le hard logout, un simple relais de fin pour
    /// `logout()`) et le stocke ; les suivants reçoivent ce même `task` sans jamais exécuter
    /// `makeTask`, donc sans jamais rejouer le travail.
    private func claimOrJoinTermination(
        makingTask makeTask: () -> Task<Void, Never>
    ) -> (isClaimant: Bool, task: Task<Void, Never>) {
        termination.withLock { stored in
            if let stored {
                return (false, stored)
            }
            let task = makeTask()
            stored = task
            return (true, task)
        }
    }
}
