import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``NotificationContentResolving`` adossée au SDK Rust, pour l'extension.
///
/// N'expose aucune sync, par construction : en synchroniser une depuis l'extension corromprait
/// l'état de l'application, qui partage le store (spec de référence, §8).
public final class RustNotificationResolver: NotificationContentResolving {
    /// Retient, côté Rust, le client interne du SDK : libéré par ``deinit`` avant ``client``
    /// (voir ``RustMatrixSession``, `Dependents` — le dernier `Arc<ClientInner>` libéré hors du
    /// runtime Tokio fait paniquer la fermeture des connexions SQLite, et le processus s'arrête).
    /// Écrit seulement par l'initialiseur et par ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var notificationClient: (any NotificationClientDriving)?
    /// Retenus pour la durée du résolveur : le client porte le store, le restorer le
    /// `SessionDelegate` dont le SDK se sert pour rafraîchir le jeton. Le client part en dernier.
    private let client: Client?
    private let restorer: SessionRestorer?

    init(notificationClient: any NotificationClientDriving, client: Client? = nil, restorer: SessionRestorer? = nil) {
        self.notificationClient = notificationClient
        self.client = client
        self.restorer = restorer
    }

    deinit {
        withExtendedLifetime(client) {
            notificationClient = nil
        }
    }

    /// Ouvre la session persistée dans `storage` avec le rôle d'extension.
    public static func open(storage: MatrixStorage) async throws -> RustNotificationResolver {
        try await SessionRestorer(storage: storage, role: .notificationExtension).makeNotificationResolver()
    }

    public func notification(roomID: RoomID, eventID: EventID) async throws -> NotificationResult {
        let status: NotificationStatus
        do {
            guard let notificationClient else {
                // Inatteignable : `notificationClient` n'est vidé que par `deinit`.
                preconditionFailure("RustNotificationResolver used after deinitialization")
            }
            status = try await notificationClient.getNotification(roomId: roomID.rawValue, eventId: eventID.rawValue)
        } catch {
            throw ErrorMapper.map(error)
        }
        return try NotificationMapper.result(from: status, roomID: roomID, eventID: eventID)
    }
}
