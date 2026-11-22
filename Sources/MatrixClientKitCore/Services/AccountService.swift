import Foundation

/// Account management: the authorization server's pages, ignored users, and deactivation.
public protocol AccountService: Sendable {
    /// The page to open in a browser (`ASWebAuthenticationSession` or Safari) for `action`;
    /// `nil` when the homeserver does not delegate account management to an authorization
    /// server — then the account is managed by the homeserver itself.
    func managementURL(for action: AccountManagementAction) async throws -> URL?

    /// A stream of snapshots of the users the current user ignores, starting with the current
    /// list. Every access opens an independent subscription.
    ///
    /// When reading the initial list fails before any update arrived, the stream ends without any
    /// value; if an update already arrived, the stream stays open.
    var ignoredUsers: AsyncStream<[UserID]> { get }
    /// Ignores a user: their messages and invitations no longer reach this account.
    func ignore(_ user: UserID) async throws
    /// Stops ignoring a user.
    func unignore(_ user: UserID) async throws

    /// Deactivates the account for good, authenticating with its password.
    ///
    /// A session opened through OAuth is refused before any server call, with
    /// ``MatrixError/unexpected(message:details:)`` pointing to
    /// ``managementURL(for:)`` with ``AccountManagementAction/deactivateAccount``.
    /// On success the local data is erased and the authentication state becomes signed out. The
    /// erasure is best effort: once the server has deactivated the account, a local erasure error
    /// is not reported, since the call did succeed. On failure nothing is erased and the session
    /// stays usable.
    ///
    /// A refused password throws ``MatrixError/authentication(_:)`` with `.invalidCredentials`; a
    /// session that already ended throws ``MatrixError/unexpected(message:details:)``.
    ///
    /// - Important: a failure can be reported although the account was deactivated on the server
    ///   (for example the network dropping on the second request, after the server accepted the
    ///   first authenticated one). The session is then dead: the next sync receives
    ///   `M_UNKNOWN_TOKEN`, the hard logout erases the local data and publishes signed out.
    ///
    /// - Parameters:
    ///   - password: The account's password.
    ///   - eraseData: Whether the homeserver is asked to erase the user's data too.
    func deactivate(password: String, eraseData: Bool) async throws
}
