import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixSession`` adossée au SDK Rust.
public final class RustMatrixSession: MatrixClientKitCore.MatrixSession {
    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController

    private let client: Client
    private let persistence: SessionPersistence
    private let localStore: LocalStore

    private init(
        client: Client,
        persistence: SessionPersistence,
        localStore: LocalStore,
        userID: UserID,
        deviceID: DeviceID,
        rooms: any RoomService,
        sync: any SyncController
    ) {
        self.client = client
        self.persistence = persistence
        self.localStore = localStore
        self.userID = userID
        self.deviceID = deviceID
        self.rooms = rooms
        self.sync = sync
    }

    static func make(
        client: Client,
        persistence: SessionPersistence,
        localStore: LocalStore
    ) async throws -> RustMatrixSession {
        do {
            let session = try client.session()
            let data = try SessionMapper.sessionData(from: session)
            let syncService = try await client.syncService().finish()

            return RustMatrixSession(
                client: client,
                persistence: persistence,
                localStore: localStore,
                userID: data.userID,
                deviceID: data.deviceID,
                rooms: RustRoomService(roomListService: syncService.roomListService()),
                sync: RustSyncController(service: syncService)
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Ferme la session côté serveur et efface toutes les données locales : session persistée,
    /// store SQLite (historique **et** store crypto) et clé de chiffrement associée.
    ///
    /// - Important: l'effacement local doit survenir même si l'appel serveur échoue — un
    ///   utilisateur qui se déconnecte hors ligne ne doit pas rester connecté localement.
    ///   L'erreur serveur, elle, doit tout de même remonter à l'appelant. Si l'effacement local
    ///   échoue à son tour dans cette branche, l'échec est volontairement avalé (`try?`) : c'est
    ///   l'erreur serveur, plus significative pour l'appelant, qui doit rester celle qu'il voit —
    ///   pas un échec secondaire de nettoyage local.
    ///
    /// - Important: `Client.logout()` amont ne fait que la déconnexion côté serveur ; il ne
    ///   supprime rien en local. Sans la purge ci-dessous, l'identité d'appareil et les clés de
    ///   room Megolm resteraient sur disque après une déconnexion.
    public func logout() async throws {
        do {
            await sync.stop()
            try await client.logout()
        } catch {
            try? persistence.clear()
            try? localStore.purge()
            throw ErrorMapper.map(error)
        }
        try persistence.clear()
        try localStore.purge()
    }
}
