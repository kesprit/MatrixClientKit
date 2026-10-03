import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixSession`` adossée au SDK Rust.
public final class RustMatrixSession: MatrixClientKitCore.MatrixSession {
    public let userID: UserID
    public let deviceID: DeviceID
    public var rooms: any RoomService { live.rooms }
    public var sync: any SyncController { live.sync }
    public var encryption: any EncryptionService { live.encryption }
    public var notifications: any NotificationService { live.notifications }

    /// Le store local de la session, et l'adresse du serveur qui l'a émise.
    let segment: StoreSegment
    let homeserverURL: URL

    /// Libéré en **dernier**, par ``deinit`` : voir ``Dependents``.
    private let client: Client
    /// Tenu pour toute la vie de la session : sans lui, le ramassage d'une connexion ultérieure
    /// dans ce processus emporterait ce store dès que la session persistée en désigne un autre
    /// (spec 0.4, §5.4).
    private let lease: StoreLease
    /// Retenu pour la durée de la session : il porte le `SessionDelegate` dont le SDK se sert à
    /// chaque rafraîchissement de jeton.
    private let restorer: SessionRestorer

    /// Tout ce que la session retient et qui retient, côté Rust, le client interne du SDK
    /// (`Arc<ClientInner>`) : services FFI, cycle de vie (sa closure d'arrêt vise le
    /// `SyncService`), delegate et son handle, tâche de surveillance.
    ///
    /// Pourquoi un conteneur à part : le dernier `Arc<ClientInner>` doit tomber dans le runtime
    /// Tokio, sans quoi la fermeture des connexions SQLite (`deadpool`) panique — « there is no
    /// reactor running » — dans un destructeur, et le processus s'arrête (abort). Le `Drop` du
    /// `Client` FFI entre dans ce runtime ; celui d'un `SyncService` ou d'un `RoomListService`,
    /// libéré sur un fil Swift, non. Il faut donc que le `Client` parte en dernier. L'ordre de
    /// destruction des propriétés stockées ne se pilote pas ; ``deinit`` libère donc ce conteneur
    /// explicitement, client encore vivant. Constaté contre Synapse : `logout()` puis libération
    /// de la session.
    private struct Dependents: Sendable {
        let rooms: any RoomService
        let sync: any SyncController
        let encryption: any EncryptionService
        let notifications: any NotificationService
        let lifecycle: SessionLifecycle
        /// Retenus pour la durée de la session : un delegate libéré ne signalerait plus aucune
        /// déconnexion serveur, et l'annulation du handle désabonnerait le delegate.
        let authDelegate: AuthDelegate
        let authDelegateHandle: TaskHandle?
        /// Obtient le contrôleur de vérification dès que l'amont le permet (voir
        /// ``watchForVerificationController(verification:encryption:)``).
        let controllerWatcher: Task<Void, Never>
    }

    /// Écrit seulement par l'initialiseur et par ``deinit``, qui ont tous deux un accès exclusif :
    /// aucune lecture concurrente n'est possible, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var dependents: Dependents?

    private var live: Dependents {
        guard let dependents else {
            // Inatteignable : `dependents` n'est vidé que par `deinit`.
            preconditionFailure("RustMatrixSession used after deinitialization")
        }
        return dependents
    }

    private var lifecycle: SessionLifecycle { live.lifecycle }

    /// Couture de test : le client amont, pour jouer l'« appareil qui accorde » dans la suite
    /// d'intégration de la connexion par QR. Portée `package`, jamais publique.
    package var underlyingClient: Client { client }

    private init(
        userID: UserID,
        deviceID: DeviceID,
        rooms: any RoomService,
        sync: any SyncController,
        encryption: any EncryptionService,
        notifications: any NotificationService,
        segment: StoreSegment,
        homeserverURL: URL,
        client: Client,
        lease: StoreLease,
        restorer: SessionRestorer,
        lifecycle: SessionLifecycle,
        authDelegate: AuthDelegate,
        authDelegateHandle: TaskHandle?,
        controllerWatcher: Task<Void, Never>
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.segment = segment
        self.homeserverURL = homeserverURL
        self.client = client
        self.lease = lease
        self.restorer = restorer
        self.dependents = Dependents(
            rooms: rooms,
            sync: sync,
            encryption: encryption,
            notifications: notifications,
            lifecycle: lifecycle,
            authDelegate: authDelegate,
            authDelegateHandle: authDelegateHandle,
            controllerWatcher: controllerWatcher
        )
    }

    deinit {
        // Les dépendants d'abord, le client ensuite : voir ``Dependents``.
        withExtendedLifetime(client) {
            dependents?.controllerWatcher.cancel()
            dependents?.authDelegateHandle?.cancel()
            dependents = nil
        }
    }

    public var authState: AsyncStream<AuthState> {
        lifecycle.authState
    }

    static func make(
        client: Client,
        restorer: SessionRestorer,
        localStore: LocalStore,
        lease: StoreLease
    ) async throws -> RustMatrixSession {
        do {
            let persistence = restorer.persistence
            let session = try client.session()
            let data = try SessionMapper.sessionData(from: session, storeID: localStore.segment.storeID)
            let syncService = try await client.syncService().finish()
            let sync = RustSyncController(service: syncService)

            let verification = RustSessionVerification(
                ownUserID: data.userID,
                loadController: { try await client.getSessionVerificationController() }
            )
            let encryption = RustEncryptionService(
                encryption: client.encryption(),
                sessionVerification: verification
            )

            let notifications = RustNotificationService(
                pushers: client,
                settings: await client.getNotificationSettings(),
                roomFacts: { roomID in
                    guard let room = try client.getRoom(roomId: roomID) else { return nil }
                    // Même définition qu'Element X (Task 1, constat 4) : l'amont en déduit le
                    // réglage par défaut d'un salon.
                    return RoomFacts(isEncrypted: await room.isEncrypted(), isOneToOne: room.activeMembersCount() == 2)
                }
            )

            // Référence faible : le cycle de vie peut survivre à la session (closure d'un flux OAuth
            // de reconnexion), et ne doit pas faire du `SyncService` le dernier détenteur du client
            // interne (voir ``Dependents``). La session libérée, plus rien n'est à arrêter.
            let lifecycle = SessionLifecycle(
                stopSync: { [weak syncService] in await syncService?.stop() },
                erase: { try eraseLocalData(persistence: persistence, localStore: localStore) }
            )
            let authDelegate = AuthDelegate(lifecycle: lifecycle)
            let authDelegateHandle = try client.setDelegate(delegate: authDelegate)

            return RustMatrixSession(
                userID: data.userID,
                deviceID: data.deviceID,
                rooms: RustRoomService(roomListService: syncService.roomListService()),
                sync: sync,
                encryption: encryption,
                notifications: notifications,
                segment: localStore.segment,
                homeserverURL: data.homeserverURL,
                client: client,
                lease: lease,
                restorer: restorer,
                lifecycle: lifecycle,
                authDelegate: authDelegate,
                authDelegateHandle: authDelegateHandle,
                controllerWatcher: watchForVerificationController(verification: verification, encryption: encryption)
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Ferme la session côté serveur et efface toutes les données locales : session persistée,
    /// store SQLite (historique **et** store crypto) et clé de chiffrement associée.
    ///
    /// - Important: `Client.logout()` amont ne fait que la déconnexion côté serveur ; il ne
    ///   supprime rien en local. Sans l'effacement orchestré par ``SessionLifecycle``, l'identité
    ///   d'appareil et les clés de room Megolm resteraient sur disque après une déconnexion.
    public func logout() async throws {
        let client = client
        try await lifecycle.logout {
            try await client.logout()
        }
    }

    // Se reconnecte sur le même appareil après un soft logout (spec 0.4, §4.6, §5.5).
    //
    // L'amont pose une session une seule fois par client : la reconnexion construit un client
    // neuf sur le même store, avec le même appareil, et rend une nouvelle session. La
    // réservation passe avant l'arrêt de la sync : une seconde reconnexion concurrente, ou une
    // terminaison déjà revendiquée, est refusée sans rien toucher. En cas d'échec, la réservation
    // est rendue et la session reste en `.softLoggedOut`, intacte.
    public func reauthenticate(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        let attempt = try await beginReauthenticationAttempt()
        do {
            try await attempt.authenticate(credentials, deviceID: deviceID)
            let session = try await attempt.succeed(expecting: userID)
            lifecycle.markReplaced()
            return session
        } catch {
            attempt.fail()
            lifecycle.releaseReauthentication()
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    // Variante OAuth de ``reauthenticate(_:)`` : la réservation est tenue pendant toute la vie du
    // flux, et rendue ou consommée à son issue.
    public func beginOAuthReauthentication(
        _ configuration: MatrixClientKitCore.OAuthConfiguration
    ) async throws -> any OAuthLoginFlow {
        let attempt = try await beginReauthenticationAttempt()
        let lifecycle = lifecycle
        return try await RustOAuthLoginFlow.begin(
            attempt: attempt, configuration: configuration, prompt: nil, loginHint: userID.rawValue,
            deviceID: deviceID, expecting: userID,
            onEnd: { succeeded in
                if succeeded {
                    lifecycle.markReplaced()
                } else {
                    lifecycle.releaseReauthentication()
                }
            }
        )
    }

    /// Réserve la session, arrête sa sync et ouvre une tentative sur son store. La réservation
    /// est rendue si la tentative ne s'ouvre pas.
    private func beginReauthenticationAttempt() async throws -> LoginAttempt {
        try lifecycle.reserveForReauthentication()
        await lifecycle.stopSyncForReplacement()
        do {
            return try await LoginAttempt.begin(
                restorer: restorer, target: .homeserver(homeserverURL), reusing: segment
            )
        } catch {
            lifecycle.releaseReauthentication()
            throw error
        }
    }

    /// Obtient le contrôleur de vérification le plus tôt possible.
    ///
    /// Le delegate doit être posé avant qu'une demande entrante n'arrive, faute de quoi elle est
    /// perdue. Or l'amont n'accorde le contrôleur qu'une fois l'identité de l'utilisateur présente
    /// dans le store local (spec 0.2, §2.8 et §6.2). Le signal fiable de ce chargement est l'état
    /// de vérification de l'appareil : il change quand l'identité devient connue, y compris après
    /// l'amorçage du cross-signing d'un compte neuf. L'état de la sync, lui, passe à `.running`
    /// avant ce chargement et y reste — s'y fier laisserait le contrôleur jamais obtenu.
    ///
    /// Tentative à chaque valeur du flux, qui commence par la valeur courante, jusqu'au premier
    /// succès (voir ``retryUntilSuccess(on:attempt:)``).
    private static func watchForVerificationController(
        verification: RustSessionVerification,
        encryption: RustEncryptionService
    ) -> Task<Void, Never> {
        // Référence faible : une tâche annulée ne libère pas sa closure tout de suite, et ne doit
        // pas prolonger la vérification (et le `Client` qu'elle capture) après la session.
        retryUntilSuccess(on: encryption.verificationStatus) { [weak verification] in
            guard let verification else { return true }
            return (try? await verification.ensureController()) != nil
        }
    }

    /// Appelle `attempt` à chaque valeur de `values`, et s'arrête au premier appel qui réussit —
    /// les valeurs suivantes ne déclenchent plus rien.
    static func retryUntilSuccess(
        on values: AsyncStream<VerificationStatus>,
        attempt: @escaping @Sendable () async -> Bool
    ) -> Task<Void, Never> {
        Task {
            for await _ in values {
                if await attempt() { return }
            }
        }
    }

    /// Efface la session persistée puis le store local. Les deux effacements sont tentés même si
    /// le premier échoue — une session effacée dont le store crypto resterait sur disque est
    /// précisément ce que la purge existe pour éviter ; la première erreur est relayée.
    private static func eraseLocalData(persistence: SessionPersistence, localStore: LocalStore) throws {
        var firstError: (any Error)?
        do {
            try persistence.clear()
        } catch {
            firstError = error
        }
        do {
            try localStore.purge()
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }
}
