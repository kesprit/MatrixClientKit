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
    /// Push notifications: this device's pusher, and how much each room notifies.
    var notifications: any NotificationService { get }

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
    ///
    /// Only one session is saved for the next launch: the most recent successful sign-in. Ending
    /// an older session still open in the process erases that session's own data but keeps the
    /// saved one; the same holds when the homeserver ends it.
    func logout() async throws

    /// Signs in again on the same device after ``AuthState/softLoggedOut``, keeping its
    /// encryption keys, and returns the new session.
    ///
    /// This session is then over: it reports ``AuthState/signedOut`` and its data belongs to the
    /// new session — release it. If signing in fails, this session stays
    /// ``AuthState/softLoggedOut``, untouched: the user can try again, but its syncing remains
    /// stopped. A second concurrent call throws ``MatrixError/unexpected(message:details:)``.
    ///
    /// - Throws: ``MatrixError/unexpected(message:details:)`` when the session is not soft-logged
    ///   out, or when another reauthentication is already running; ``MatrixError/authentication(_:)``
    ///   when the credentials are refused or belong to another account.
    func reauthenticate(_ credentials: Credentials) async throws -> any MatrixSession

    /// Like ``reauthenticate(_:)``, through OAuth: the flow's ``OAuthLoginFlow/complete(callbackURL:)``
    /// returns the new session.
    func beginOAuthReauthentication(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow
}
