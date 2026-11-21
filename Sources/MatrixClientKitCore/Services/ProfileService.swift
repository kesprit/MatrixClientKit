import Foundation

/// Reads and edits the current user's profile, and publishes their presence.
public protocol ProfileService: Sendable {
    /// Fetches a user's global profile from the homeserver; pass ``MatrixSession/userID`` for
    /// the current user's.
    ///
    /// Nothing is cached: every call queries the server.
    func profile(of user: UserID) async throws -> UserProfile
    /// Changes the current user's display name.
    ///
    /// The name is not validated: an empty string is sent as is. The current user's profile is
    /// not observable, so update your display yourself afterwards.
    func setDisplayName(_ name: String) async throws
    /// Uploads `data` and makes it the current user's avatar.
    ///
    /// A media larger than the homeserver accepts throws ``MatrixError/unexpected(message:details:)``.
    func setAvatar(_ data: Data, mimeType: String) async throws
    /// Removes the current user's avatar.
    func removeAvatar() async throws
    /// Publishes the current user's presence now, and keeps it for the following syncs.
    ///
    /// The state is applied to the following syncs even when this call throws. It is not
    /// persisted: publish it again at every launch.
    func setPresence(_ presence: Presence) async throws
}
