import Foundation

/// Whether a session is still authenticated with its homeserver. See ``MatrixSession/authState``.
public enum AuthState: Sendable, Hashable {
    /// The session is authenticated.
    case signedIn
    /// The homeserver expired the session, but lets this device sign in again without losing its
    /// encryption keys. Nothing was erased. Until same-device sign-in is supported, call
    /// ``MatrixSession/logout()`` and sign in again.
    case softLoggedOut
    /// The session is over: the homeserver revoked it, or ``MatrixSession/logout()`` completed.
    /// Everything stored locally for it has been erased.
    case signedOut
}
