import Foundation

/// Whether a session is still authenticated with its homeserver. See ``MatrixSession/authState``.
public enum AuthState: Sendable, Hashable {
    /// The session is authenticated.
    case signedIn
    /// The homeserver expired the session, but lets this device sign in again without losing its
    /// encryption keys. Nothing was erased. Call ``MatrixSession/reauthenticate(_:)`` or
    /// ``MatrixSession/beginOAuthReauthentication(_:)`` to sign in again on the same device.
    case softLoggedOut
    /// The session is over: the homeserver revoked it, ``MatrixSession/logout()`` completed, or it
    /// was replaced by a reauthenticated session. In the first two cases, everything stored locally
    /// for it has been erased; a replaced session's data now belongs to its replacement.
    case signedOut
}
