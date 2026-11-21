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
    /// When reading the initial list fails, the stream ends without any value.
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
    /// On success the local data is erased as after `logout()` and the authentication state
    /// becomes signed out. On failure nothing is erased and the session stays usable.
    ///
    /// - Parameters:
    ///   - password: The account's password.
    ///   - eraseData: Whether the homeserver is asked to erase the user's data too.
    func deactivate(password: String, eraseData: Bool) async throws
}
