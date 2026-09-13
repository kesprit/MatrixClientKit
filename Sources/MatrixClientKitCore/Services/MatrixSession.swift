/// Session authentifiée : tous les services en découlent.
public protocol MatrixSession: Sendable {
    /// Identifiant de l'utilisateur authentifié.
    var userID: UserID { get }
    /// Identifiant de l'appareil sur lequel la session est ouverte.
    var deviceID: DeviceID { get }
    /// Accès aux rooms et à leur liste observable.
    var rooms: any RoomService { get }
    /// Pilote la synchronisation avec le homeserver.
    var sync: any SyncController { get }

    /// Ferme la session côté serveur et efface les données persistées localement.
    func logout() async throws
}
