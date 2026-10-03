import Foundation
import MatrixClientKitCore

/// A drivable ``MatrixClient`` for testing sign-in and launch flows.
///
/// ``login(_:)`` returns or throws ``loginResult`` and records the credentials it received;
/// ``restoreSession()`` returns or throws ``restoreResult``, `nil` by default.
///
/// ``loginDetails()`` returns ``loginDetailsResult``; ``beginOAuthLogin(_:prompt:loginHint:)``
/// records its request and returns ``oauthFlow``; ``loginWithQRCode(_:)`` returns ``qrCodeLogin``.
///
/// ``Matrix/restoreSession(storage:)`` is a static function and cannot be replaced by this mock:
/// inject it into your code as a closure instead — see <doc:TestingWithMocks>.
public final class MockMatrixClient: MatrixClient, @unchecked Sendable {
    private let lock = NSLock()

    public let homeserver: URL

    private var _loginResult: Result<MockMatrixSession, MatrixError>
    private var _restoreResult: Result<MockMatrixSession?, MatrixError> = .success(nil)
    private var _loginAttempts: [Credentials] = []
    private var _loginDetailsResult: Result<LoginDetails, MatrixError>
    private var _oauthLoginError: MatrixError?
    private var _oauthRequests: [OAuthRequest] = []

    /// The flow ``beginOAuthLogin(_:prompt:loginHint:)`` returns.
    public let oauthFlow = MockOAuthLoginFlow()
    /// The login ``loginWithQRCode(_:)`` returns.
    public let qrCodeLogin = MockQRCodeLogin()

    /// A recorded call to ``beginOAuthLogin(_:prompt:loginHint:)``.
    public struct OAuthRequest: Sendable, Hashable {
        public let configuration: OAuthConfiguration
        public let prompt: OAuthPrompt?
        public let loginHint: String?

        public init(configuration: OAuthConfiguration, prompt: OAuthPrompt?, loginHint: String?) {
            self.configuration = configuration
            self.prompt = prompt
            self.loginHint = loginHint
        }
    }

    public init(
        homeserver: URL = URL(string: "https://matrix.org")!,
        loginResult: Result<MockMatrixSession, MatrixError> = .success(MockMatrixSession())
    ) {
        self.homeserver = homeserver
        self._loginResult = loginResult
        self._loginDetailsResult = .success(SampleData.loginDetails(homeserver: homeserver))
    }

    /// What ``loginDetails()`` returns or throws. Password-only by default.
    public var loginDetailsResult: Result<LoginDetails, MatrixError> {
        get { lock.withLock { _loginDetailsResult } }
        set { lock.withLock { _loginDetailsResult = newValue } }
    }

    /// The error ``beginOAuthLogin(_:prompt:loginHint:)`` throws instead of returning ``oauthFlow``.
    public var oauthLoginError: MatrixError? {
        get { lock.withLock { _oauthLoginError } }
        set { lock.withLock { _oauthLoginError = newValue } }
    }

    /// Every call to ``beginOAuthLogin(_:prompt:loginHint:)``, in order.
    public var oauthRequests: [OAuthRequest] {
        lock.withLock { _oauthRequests }
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

    public func loginDetails() async throws -> LoginDetails {
        try loginDetailsResult.get()
    }

    public func beginOAuthLogin(
        _ configuration: OAuthConfiguration,
        prompt: OAuthPrompt?,
        loginHint: String?
    ) async throws -> any OAuthLoginFlow {
        let error = lock.withLock {
            _oauthRequests.append(OAuthRequest(configuration: configuration, prompt: prompt, loginHint: loginHint))
            return _oauthLoginError
        }
        if let error { throw error }
        return oauthFlow
    }

    public func loginWithQRCode(_ configuration: OAuthConfiguration) -> any QRCodeLogin {
        qrCodeLogin
    }
}
