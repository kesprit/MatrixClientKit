/// An authenticated session: every service is reached through it.
public protocol MatrixSession: Sendable {
    /// The authenticated user's identifier.
    var userID: UserID { get }
    /// The identifier of the device this session is open on.
    var deviceID: DeviceID { get }
    /// Access to rooms and to the observable room list.
    var rooms: any RoomService { get }
    /// Drives syncing with the homeserver.
    var sync: any SyncController { get }

    /// Ends the session server-side and erases everything stored locally.
    func logout() async throws
}
