import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixSession`` adossée au SDK Rust.
public final class RustMatrixSession: MatrixClientKitCore.MatrixSession {
    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController
    public let encryption: any EncryptionService

    private let client: Client
    /// Retenu pour la durée de la session : il porte le `SessionDelegate` dont le SDK se sert à
    /// chaque rafraîchissement de jeton.
    private let restorer: SessionRestorer
    private let lifecycle: SessionLifecycle

    /// Retenus pour la durée de la session : un delegate libéré ne signalerait plus aucune
    /// déconnexion serveur, et l'annulation du handle désabonnerait le delegate.
    private let authDelegate: AuthDelegate
    private let authDelegateHandle: TaskHandle?

    /// Obtient le contrôleur de vérification dès que l'amont le permet (voir
    /// ``watchForVerificationController(verification:sync:)``).
    private let controllerWatcher: Task<Void, Never>

    private init(
        userID: UserID,
        deviceID: DeviceID,
        rooms: any RoomService,
        sync: any SyncController,
        encryption: any EncryptionService,
        client: Client,
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
        self.client = client
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
        localStore: LocalStore
    ) async throws -> RustMatrixSession {
        do {
            let persistence = restorer.persistence
            let session = try client.session()
            let data = try SessionMapper.sessionData(from: session)
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
                client: client,
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
    /// succès.
    private static func watchForVerificationController(
        verification: RustSessionVerification,
        encryption: RustEncryptionService
    ) -> Task<Void, Never> {
        Task {
            for await _ in encryption.verificationStatus {
                if (try? await verification.ensureController()) != nil { return }
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
