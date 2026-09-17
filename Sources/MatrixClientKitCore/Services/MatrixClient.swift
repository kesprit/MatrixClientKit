import Foundation

/// Sign-in credentials. v0.1 covers passwords; OAuth arrives in v0.4.
public enum Credentials: Sendable, Hashable {
    /// Username-and-password sign-in, with an optional device name.
    case password(username: String, password: String, deviceName: String?)
}

extension Credentials: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted description: never exposes the password.
    public var description: String {
        switch self {
        case let .password(username, _, deviceName):
            let device = deviceName ?? "nil"
            return "Credentials.password(username: \(username), password: <redacted>, deviceName: \(device))"
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
}
