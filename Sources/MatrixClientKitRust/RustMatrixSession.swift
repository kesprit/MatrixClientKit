import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixSession`` adossée au SDK Rust.
public final class RustMatrixSession: MatrixClientKitCore.MatrixSession {
    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController
    public let encryption: any EncryptionService
    public let notifications: any NotificationService

    /// Le store local de la session, et l'adresse du serveur qui l'a émise.
    let segment: StoreSegment
    let homeserverURL: URL

    private let client: Client
    /// Tenu pour toute la vie de la session : sans lui, le ramassage d'une connexion ultérieure
    /// dans ce processus emporterait ce store dès que la session persistée en désigne un autre
    /// (spec 0.4, §5.4).
    private let lease: StoreLease
    /// Retenu pour la durée de la session : il porte le `SessionDelegate` dont le SDK se sert à
    /// chaque rafraîchissement de jeton.
    private let restorer: SessionRestorer
    private let lifecycle: SessionLifecycle

    /// Retenus pour la durée de la session : un delegate libéré ne signalerait plus aucune
    /// déconnexion serveur, et l'annulation du handle désabonnerait le delegate.
    private let authDelegate: AuthDelegate
    private let authDelegateHandle: TaskHandle?

    /// Obtient le contrôleur de vérification dès que l'amont le permet (voir
    /// ``watchForVerificationController(verification:encryption:)``).
    private let controllerWatcher: Task<Void, Never>

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
        self.rooms = rooms
        self.sync = sync
        self.encryption = encryption
        self.notifications = notifications
        self.segment = segment
        self.homeserverURL = homeserverURL
        self.client = client
        self.lease = lease
        self.restorer = restorer
        self.lifecycle = lifecycle
        self.authDelegate = authDelegate
        self.authDelegateHandle = authDelegateHandle
        self.controllerWatcher = controllerWatcher
    }

    deinit {
        controllerWatcher.cancel()
        authDelegateHandle?.cancel()
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

            let lifecycle = SessionLifecycle(
                stopSync: { await syncService.stop() },
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

    /// Se reconnecte sur le même appareil après un soft logout (spec 0.4, §4.6, §5.5).
    ///
    /// L'amont pose une session une seule fois par client : la reconnexion construit un client
    /// neuf sur le même store, avec le même appareil, et rend une nouvelle session. La
    /// réservation passe avant l'arrêt de la sync : une seconde reconnexion concurrente, ou une
    /// terminaison déjà revendiquée, est refusée sans rien toucher. En cas d'échec, la réservation
    /// est rendue et la session reste en `.softLoggedOut`, intacte.
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

    /// Variante OAuth de ``reauthenticate(_:)`` : la réservation est tenue pendant toute la vie du
    /// flux, et rendue ou consommée à son issue.
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
        retryUntilSuccess(on: encryption.verificationStatus) {
            (try? await verification.ensureController()) != nil
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
