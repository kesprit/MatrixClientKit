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
    /// End-to-end encryption: this device's verification, recovery and key backup.
    var encryption: any EncryptionService { get }

    /// A stream of the session's authentication state, starting with the current value. Every
    /// access opens an independent subscription.
    ///
    /// Observe it to learn that the homeserver ended the session while the application was
    /// running — for instance after the user removed this device from another one. When it
    /// reports ``AuthState/signedOut``, everything stored locally for the session has already been
    /// erased.
    var authState: AsyncStream<AuthState> { get }

    /// Ends the session server-side and erases everything stored locally.
    ///
    /// Local data is erased even when the server call fails, and the error is then thrown. After
    /// ``AuthState/softLoggedOut``, the server is expected to reject the call: the local cleanup
    /// still happens and nothing is thrown. After ``AuthState/signedOut``, this does nothing.
    func logout() async throws
}
