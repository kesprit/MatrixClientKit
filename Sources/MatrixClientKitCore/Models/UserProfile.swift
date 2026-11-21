/// A user's global profile.
public struct UserProfile: Sendable, Hashable {
    /// The user the profile belongs to.
    public let userID: UserID
    /// The user's display name, when they set one.
    public let displayName: String?
    /// Pass it to ``MediaService`` to display the avatar.
    public let avatar: MediaSource?

    /// Creates a profile.
    public init(userID: UserID, displayName: String?, avatar: MediaSource?) {
        self.userID = userID
        self.displayName = displayName
        self.avatar = avatar
    }
}

/// What the current user's contacts see of their availability.
public enum Presence: Sendable, Hashable {
    /// Connected and active.
    case online
    /// Connected but away — the state until the application sets another one.
    case unavailable
    /// Not connected.
    case offline
}
