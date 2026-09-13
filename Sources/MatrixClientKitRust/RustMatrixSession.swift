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

    private init(
        client: Client,
        persistence: SessionPersistence,
        userID: UserID,
        deviceID: DeviceID,
        rooms: any RoomService,
        sync: any SyncController
    ) {
        self.client = client
        self.persistence = persistence
        self.userID = userID
        self.deviceID = deviceID
        self.rooms = rooms
        self.sync = sync
    }

    static func make(client: Client, persistence: SessionPersistence) async throws -> RustMatrixSession {
        do {
            let session = try client.session()
            let data = try SessionMapper.sessionData(from: session)
            let syncService = try await client.syncService().finish()

            return RustMatrixSession(
                client: client,
                persistence: persistence,
                userID: data.userID,
                deviceID: data.deviceID,
                rooms: RustRoomService(roomListService: syncService.roomListService()),
                sync: RustSyncController(service: syncService)
            )
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    /// Ferme la session côté serveur et efface les données persistées localement.
    ///
    /// - Important: l'effacement local doit survenir même si l'appel serveur échoue — un
    ///   utilisateur qui se déconnecte hors ligne ne doit pas rester connecté localement.
    ///   L'erreur serveur, elle, doit tout de même remonter à l'appelant.
    public func logout() async throws {
        do {
            await sync.stop()
            try await client.logout()
        } catch {
            try? await persistence.clear()
            throw ErrorMapper.map(error)
        }
        try await persistence.clear()
    }
}
