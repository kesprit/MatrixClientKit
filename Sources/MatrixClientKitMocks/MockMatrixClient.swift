import Foundation
import MatrixClientKitCore

/// A drivable ``MatrixClient`` for testing sign-in and launch flows.
///
/// ``login(_:)`` returns or throws ``loginResult`` and records the credentials it received;
/// ``restoreSession()`` returns or throws ``restoreResult``, `nil` by default.
///
/// ``Matrix/restoreSession(storage:)`` is a static function and cannot be replaced by this mock:
/// inject it into your code as a closure instead — see <doc:TestingWithMocks>.
public final class MockMatrixClient: MatrixClient, @unchecked Sendable {
    private let lock = NSLock()

    public let homeserver: URL

    private var _loginResult: Result<MockMatrixSession, MatrixError>
    private var _restoreResult: Result<MockMatrixSession?, MatrixError> = .success(nil)
    private var _loginAttempts: [Credentials] = []

    public init(
        homeserver: URL = URL(string: "https://matrix.org")!,
        loginResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())
    ) {
        self.homeserver = homeserver
        self._loginResult = loginResult
    }

    /// What ``login(_:)`` returns or throws.
    public var loginResult: Result<MockMatrixSession, MatrixError> {
        get { lock.withLock { _loginResult } }
        set { lock.withLock { _loginResult = newValue } }
    }

    /// What ``restoreSession()`` returns or throws. `.success(nil)` by default: no stored session.
    public var restoreResult: Result<MockMatrixSession?, MatrixError> {
        get { lock.withLock { _restoreResult } }
        set { lock.withLock { _restoreResult = newValue } }
    }

    /// Every credential passed to ``login(_:)``, in order — including rejected ones.
    public var loginAttempts: [Credentials] {
        lock.withLock { _loginAttempts }
    }

    public func login(_ credentials: Credentials) async throws -> any MatrixSession {
        let result = lock.withLock {
            _loginAttempts.append(credentials)
            return _loginResult
        }
        return try result.get()
    }

    public func restoreSession() async throws -> (any MatrixSession)? {
        try restoreResult.get()
    }
}
