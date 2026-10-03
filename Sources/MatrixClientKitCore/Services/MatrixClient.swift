import Foundation

/// Sign-in credentials.
public enum Credentials: Sendable, Hashable {
    /// Username-and-password sign-in, with an optional device name.
    case password(username: String, password: String, deviceName: String?)
    /// Sign-in with an email address bound to the account, and its password.
    case email(address: String, password: String, deviceName: String?)
}

extension Credentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted description: never exposes the password.
    public var description: String {
        switch self {
        case let .password(username, _, deviceName):
            let device = deviceName ?? "nil"
            return "Credentials.password(username: \(username), password: <redacted>, deviceName: \(device))"
        case let .email(address, _, deviceName):
            let device = deviceName ?? "nil"
            return "Credentials.email(address: \(address), password: <redacted>, deviceName: \(device))"
        }
    }

    public var debugDescription: String { description }
}

/// An unauthenticated client: the entry point before a session exists.
public protocol MatrixClient: Sendable {
    /// The homeserver this client talks to.
    var homeserver: URL { get }

    /// Opens a session and persists what is needed to restore it later.
    func login(_ credentials: Credentials) async throws -> any MatrixSession

    /// Restores a previously persisted session, or returns `nil` when there is none.
    ///
    /// The session is restored with the homeserver address stored with it, which takes precedence
    /// over ``homeserver``.
    func restoreSession() async throws -> (any MatrixSession)?

    /// What the homeserver accepts for signing in. Needs no session; call it to decide which
    /// sign-in options to show.
    func loginDetails() async throws -> LoginDetails

    /// Starts signing in through the homeserver's OAuth authorization server.
    ///
    /// - Parameters:
    ///   - prompt: ``OAuthPrompt/create`` to offer account creation — only when
    ///     ``LoginDetails/oauthPrompts`` contains it.
    ///   - loginHint: a user ID to prefill, for instance `@alice:matrix.org`.
    /// - Throws: ``MatrixError/authentication(_:)`` with ``MatrixError/Authentication/unsupportedLoginType``
    ///   when the homeserver does not support OAuth.
    func beginOAuthLogin(
        _ configuration: OAuthConfiguration,
        prompt: OAuthPrompt?,
        loginHint: String?
    ) async throws -> any OAuthLoginFlow

    /// Signs this device in by showing a QR code that a device already signed in to the account
    /// scans. To scan a code instead, use `Matrix.loginWithQRCode(scanned:configuration:storage:)`.
    func loginWithQRCode(_ configuration: OAuthConfiguration) -> any QRCodeLogin
}

extension MatrixClient {
    /// Starts signing in through OAuth, without a prompt or a login hint.
    public func beginOAuthLogin(_ configuration: OAuthConfiguration) async throws -> any OAuthLoginFlow {
        try await beginOAuthLogin(configuration, prompt: nil, loginHint: nil)
    }
}
