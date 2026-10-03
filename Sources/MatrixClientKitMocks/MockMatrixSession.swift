import Foundation
import MatrixClientKitCore

/// A drivable authenticated session for tests: exposes a ready-made ``MockRoomService``,
/// ``MockSyncController``, ``MockEncryptionService`` and ``MockNotificationService``, lets you
/// push authentication states, and records calls to ``logout()``. ``reauthenticate(_:)`` returns or
/// throws ``reauthenticateResult``; ``beginOAuthReauthentication(_:)`` returns
/// ``oauthReauthenticationFlow``.
public final class MockMatrixSession: MatrixSession, @unchecked Sendable {
    private let lock = NSLock()

    public let userID: UserID
    public let deviceID: DeviceID
    public let rooms: any RoomService
    public let sync: any SyncController
    public let encryption: any EncryptionService
    public let notifications: any NotificationService

    private let authStateStream: AsyncStream<AuthState>
    private let authStateContinuation: AsyncStream<AuthState>.Continuation

    private var _didLogout = false
    private var _logoutError: MatrixError?
    private var _reauthenticateResult: Result<MockMatrixSession, MatrixError> =
        .failure(.unexpected(message: "Not soft-logged out", details: nil))
    private var _reauthenticationAttempts: [Credentials] = []

    /// The flow ``beginOAuthReauthentication(_:)`` returns. It fails to complete by default: a
    /// default success would build a ``MockMatrixSession`` that builds this flow, without end.
    public let oauthReauthenticationFlow = MockOAuthLoginFlow(
        completeResult: .failure(.unexpected(message: "Not soft-logged out", details: nil))
    )

    /// What ``reauthenticate(_:)`` returns or throws. Fails by default, like a session that is not
    /// soft-logged out.
    public var reauthenticateResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _reauthenticateResult } }
        set { lock.withLock { _reauthenticateResult = newValue } }
    }

    /// Every credential passed to ``reauthenticate(_:)``.
    public var reauthenticationAttempts: [Credentials] {
        lock.withLock { _reauthenticationAttempts }
    }

    /// True once ``logout()`` has been called, whether it threw or not.
    public var didLogout: Bool {
        lock.withLock { _didLogout }
    }

    /// The error ``logout()`` throws. `nil` by default, meaning it succeeds.
    public var logoutError: MatrixError? {
        get { lock.withLock { _logoutError } }
        set { lock.withLock { _logoutError = newValue } }
    }

    public init(
        userID: String = "@alice:matrix.org",
        deviceID: String = "DEV1",
        rooms: MockRoomService = MockRoomService(),
        sync: MockSyncController = MockSyncController(),
        encryption: MockEncryptionService = MockEncryptionService(),
        notifications: MockNotificationService = MockNotificationService()
    ) {
        self.userID = UserID(rawValue: userID) ?? UserID(rawValue: "@alice:matrix.org")!
        self.deviceID = DeviceID(rawValue: deviceID) ?? DeviceID(rawValue: "DEV1")!
        self.rooms = rooms
        self.sync = sync
        self.encryption = encryption
        self.notifications = notifications
        (authStateStream, authStateContinuation) = AsyncStream<AuthState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// The stream of authentication states. Single-consumer: iterate over it once per instance.
    /// Unlike the real session, it emits nothing until you call ``emitAuthState(_:)``.
    public var authState: AsyncStream<AuthState> { authStateStream }

    /// Pushes a value to ``authState``.
    public func emitAuthState(_ state: AuthState) {
        authStateContinuation.yield(state)
    }

    public func logout() async throws {
        let error = lock.withLock {
            _didLogout = true
            return _logoutError
        }
        if let error { throw error }
    }

    public func reauthenticate(_ credentials: Credentials) async throws -> any MatrixSession {
        let result = lock.withLock {
            _reauthenticationAttempts.append(credentials)
            return _reauthenticateResult
        }
        return try result.get()
    }

    public func beginOAuthReauthentication(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow {
        oauthReauthenticationFlow
    }
}
