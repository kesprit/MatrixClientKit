import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``NotificationContentResolving`` adossée au SDK Rust, pour l'extension.
///
/// N'expose aucune sync, par construction : en synchroniser une depuis l'extension corromprait
/// l'état de l'application, qui partage le store (spec de référence, §8).
public final class RustNotificationResolver: NotificationContentResolving {
    private let notificationClient: any NotificationClientDriving
    /// Retenus pour la durée du résolveur : le client porte le store, le restorer le
    /// `SessionDelegate` dont le SDK se sert pour rafraîchir le jeton.
    private let client: Client?
    private let restorer: SessionRestorer?

    init(notificationClient: any NotificationClientDriving, client: Client? = nil, restorer: SessionRestorer? = nil) {
        self.notificationClient = notificationClient
        self.client = client
        self.restorer = restorer
    }

    /// Ouvre la session persistée dans `storage` avec le rôle d'extension.
    public static func open(storage: MatrixStorage) async throws -> RustNotificationResolver {
        try await SessionRestorer(storage: storage, role: .notificationExtension).makeNotificationResolver()
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        let status: NotificationStatus
        do {
            status = try await notificationClient.getNotification(roomId: roomID.rawValue, eventId: eventID.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
        return try NotificationMapper.result(from: status, roomID: roomID, eventID: eventID)
    }
}
