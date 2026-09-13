/// Session authentifiée : tous les services en découlent.
public protocol MatrixSession: Sendable {
    var userID: UserID { get }
    var deviceID: DeviceID { get }
    var rooms: any RoomService { get }
    var sync: any SyncController { get }

    /// Ferme la session côté serveur et efface les données persistées localement.
    func logout() async throws
}
