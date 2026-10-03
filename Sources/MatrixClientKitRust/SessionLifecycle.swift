import Synchronization
import MatrixClientKitCore

/// Fin de vie d'une session : déconnexion demandée par l'application, ou imposée par le serveur,
/// ou remplacement par une reconnexion sur le même appareil.
///
/// Les deux chemins de déconnexion partagent une règle : arrêt de la sync et effacement local
/// n'ont lieu qu'une fois, et `.signedOut` n'est publié qu'**après** l'effacement — une
/// application qui observe `.signedOut` peut compter sur un disque déjà propre.
final class SessionLifecycle: Sendable {
    /// Qui détient la fin de la session. Un seul état, sous un seul verrou : une terminaison et
    /// une reconnexion ne peuvent jamais se croire toutes deux propriétaires du store.
    private enum Claim {
        /// Personne : une terminaison ou une reconnexion peut revendiquer la session.
        case none
        /// Une reconnexion est en cours (spec 0.4, §5.5). `relay` se termine à son issue, quand
        /// `end` est clos ; les terminaisons arrivées entre-temps l'attendent, puis rejouent leur
        /// revendication.
        ///
        /// `cancel` annule le flux OAuth qui tient la réservation : l'application peut garder ce
        /// flux indéfiniment sans le conclure, et une terminaison l'attendrait sans fin. La
        /// première terminaison le prend et l'appelle (une seule fois) ; `terminationRequested`
        /// retient qu'elle est arrivée avant que le flux n'existe, pour que celui-ci soit annulé
        /// dès son ouverture. Une reconnexion par identifiants n'a pas de crochet : son appel
        /// réseau la borne, elle est attendue.
        case reauthenticating(
            relay: Task<Void, Never>,
            end: AsyncStream<Void>.Continuation,
            cancel: (@Sendable () async -> Void)?,
            terminationRequested: Bool
        )
        /// La tâche qui termine la session, revendiquée par le premier appelant (hard logout ou
        /// `logout()`). Sert de rendez-vous : un appelant qui arrive pendant qu'une terminaison
        /// est déjà en cours l'attend au lieu de rejouer le travail, et la retrouve déjà terminée
        /// si la session est déjà `.signedOut`.
        case terminating(Task<Void, Never>)
        /// Remplacée par une reconnexion : le store appartient à la remplaçante, plus rien ne
        /// l'efface.
        case replaced
    }

    /// Ce qu'un appelant de terminaison doit faire, décidé sous le verrou.
    private enum Decision {
        case claimed(Task<Void, Never>)
        case join(Task<Void, Never>)
        /// `cancel` : le crochet d'annulation à appeler avant d'attendre, s'il revient à cet appelant.
        case waitForReauthentication(Task<Void, Never>, cancel: (@Sendable () async -> Void)?)
        case nothing
    }

    private let broadcaster = StateBroadcaster<AuthState>(.signedIn)
    private let claim = Mutex(Claim.none)
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
    ///
    /// Pendant une reconnexion, la tâche renvoyée attend son issue avant de revendiquer à
    /// nouveau : remplacée, la session n'efface rien ; abandonnée, la terminaison a lieu.
    @discardableResult
    func handleAuthError(isSoftLogout: Bool) -> Task<Void, Never>? {
        if isSoftLogout {
            broadcaster.update { $0 == .signedIn ? .softLoggedOut : $0 }
            return nil
        }

        let decision = claimTermination {
            Task {
                await self.stopSync()
                // Un effacement en échec est avalé : la session est morte côté serveur quoi qu'il
                // arrive, et la laisser en `.signedIn` promettrait une session qui n'existe plus.
                try? self.erase()
                self.broadcaster.update { _ in .signedOut }
            }
        }
        switch decision {
        case let .claimed(task):
            return task
        case let .waitForReauthentication(relay, cancel):
            return Task {
                await cancel?()
                await relay.value
                await self.handleAuthError(isSoftLogout: false)?.value
            }
        case .join, .nothing:
            return nil
        }
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
    ///   encore `.signedOut`) à un appelant qui croirait la déconnexion terminée. Pendant une
    ///   reconnexion, il attend son issue : remplacée, la session ressort sans rien effacer ni
    ///   appeler le serveur ; abandonnée, la déconnexion a lieu normalement. Une reconnexion OAuth
    ///   est d'abord annulée (voir ``registerReauthenticationCancel(_:)``) : sauf `complete` déjà
    ///   en vol, elle est donc abandonnée.
    func logout(server: @Sendable () async throws -> Void) async throws {
        while true {
            // Un simple relais : `stream` ne porte aucune valeur, sa seule fin
            // (`continuation.finish` ci-dessous) signale que le travail réel — fait par le
            // revendicateur, plus bas — est terminé, qu'il ait réussi ou levé une erreur. Ce relais
            // n'est construit que si cet appel revendique la terminaison.
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let decision = claimTermination {
                Task {
                    var iterator = stream.makeAsyncIterator()
                    _ = await iterator.next()
                }
            }

            switch decision {
            case .claimed:
                defer { continuation.finish() }
                try await terminate(server: server)
                return
            case let .join(task):
                // Perdant : la déconnexion a de toute façon abouti (ou est en train d'aboutir)
                // ailleurs, donc pas d'erreur à lever ici — seulement attendre qu'elle le soit
                // réellement avant de ressortir, pour ne jamais laisser croire à un appelant que
                // `current` reflète déjà `.signedOut` alors que l'effacement est encore en vol.
                await task.value
                return
            case let .waitForReauthentication(relay, cancel):
                await cancel?()
                await relay.value
            case .nothing:
                return
            }
        }
    }

    /// Le travail réel de `logout()`, une fois la terminaison revendiquée.
    private func terminate(server: @Sendable () async throws -> Void) async throws {
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

    /// Réserve la session pour ``RustMatrixSession/reauthenticate(_:)`` : seule une session en
    /// soft logout, que rien d'autre ne revendique, se reconnecte sur le même appareil.
    ///
    /// La réservation est atomique avec les terminaisons : une terminaison déjà revendiquée — même
    /// si `.signedOut` n'est pas encore publié — la fait refuser, et une terminaison qui arrive
    /// ensuite attend l'issue (``releaseReauthentication()`` ou ``markReplaced()``).
    func reserveForReauthentication() throws {
        let reserved = claim.withLock { claim in
            guard case .none = claim, current == .softLoggedOut else { return false }
            let (stream, end) = AsyncStream<Void>.makeStream()
            let relay = Task {
                for await _ in stream {}
            }
            claim = .reauthenticating(relay: relay, end: end, cancel: nil, terminationRequested: false)
            return true
        }
        guard reserved else {
            throw MatrixError.unexpected(
                message: "Only a session the homeserver soft-logged out can sign in again.",
                details: "\(current)"
            )
        }
    }

    /// Pose le crochet qui annule le flux OAuth tenant la réservation ; une terminaison l'appelle
    /// au lieu d'attendre que l'application conclue le flux.
    ///
    /// - Returns: `false` si une terminaison est déjà demandée (ou si la réservation n'est plus
    ///   tenue) : le crochet n'est pas retenu, et c'est à l'appelant d'annuler le flux aussitôt.
    func registerReauthenticationCancel(_ cancel: @escaping @Sendable () async -> Void) -> Bool {
        claim.withLock { claim in
            guard case let .reauthenticating(relay, end, nil, false) = claim else { return false }
            claim = .reauthenticating(relay: relay, end: end, cancel: cancel, terminationRequested: false)
            return true
        }
    }

    /// Arrête la sync avant de céder le store à une reconnexion.
    func stopSyncForReplacement() async {
        await stopSync()
    }

    /// La reconnexion a échoué ou a été annulée : la session reste en `.softLoggedOut`, intacte,
    /// et les terminaisons qui attendaient reprennent normalement.
    func releaseReauthentication() {
        let end = claim.withLock { claim -> AsyncStream<Void>.Continuation? in
            guard case let .reauthenticating(_, end, _, _) = claim else { return nil }
            claim = .none
            return end
        }
        end?.finish()
    }

    /// La session a été remplacée par une reconnexion (spec 0.4, §5.5) : son store appartient
    /// désormais à la remplaçante. Plus rien ne l'efface — ni `logout()`, ni un hard logout
    /// tardif —, et elle publie `.signedOut`.
    func markReplaced() {
        let end = claim.withLock { claim -> AsyncStream<Void>.Continuation? in
            guard case let .reauthenticating(_, end, _, _) = claim else { return nil }
            claim = .replaced
            return end
        }
        guard let end else { return }
        // Publié avant le réveil des terminaisons en attente : elles ressortent sur un état
        // déjà `.signedOut`.
        broadcaster.update { _ in .signedOut }
        end.finish()
    }

    /// Revendique la terminaison si personne ne détient la session, sous le même verrou que la
    /// lecture — pas de fenêtre où deux appelants se croient tous deux revendicateurs. Le premier
    /// à passer ici construit `task` (le travail réel pour le hard logout, un simple relais de fin
    /// pour `logout()`) et le stocke ; les suivants reçoivent ce même `task` sans jamais exécuter
    /// `makeTask`, donc sans jamais rejouer le travail.
    private func claimTermination(makingTask makeTask: () -> Task<Void, Never>) -> Decision {
        claim.withLock { claim in
            switch claim {
            case .none:
                let task = makeTask()
                claim = .terminating(task)
                return .claimed(task)
            case let .terminating(task):
                return .join(task)
            case let .reauthenticating(relay, end, cancel, _):
                // Le crochet est pris : seule la première terminaison annule le flux.
                claim = .reauthenticating(relay: relay, end: end, cancel: nil, terminationRequested: true)
                return .waitForReauthentication(relay, cancel: cancel)
            case .replaced:
                return .nothing
            }
        }
    }
}
