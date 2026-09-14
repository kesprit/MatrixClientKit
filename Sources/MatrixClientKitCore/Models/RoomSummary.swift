import Foundation

/// The current user's membership state in a room.
public enum Membership: Sendable, Hashable {
    /// The current user has joined the room.
    case joined
    /// The current user was invited but has not joined yet.
    case invited
    /// The current user has left the room.
    case left
    /// The current user knocked on a room that requires it.
    case knocked
    /// The current user is banned from the room.
    case banned
    /// The membership state could not be determined.
    case unknown
}

/// A room as it appears in a list.
public struct RoomSummary: Sendable, Hashable, Identifiable {
    /// The room's identifier.
    public let id: RoomID
    /// The room's computed display name, when one is available.
    public let displayName: String?
    /// The room's topic, when one is set.
    public let topic: String?
    /// The room's avatar URL, when one is set.
    public let avatarURL: URL?
    /// True for a direct message rather than a group room.
    public let isDirect: Bool
    /// True when the room is end-to-end encrypted; `nil` when the encryption state could not be
    /// determined — never present that case as unencrypted.
    public let isEncrypted: Bool?
    /// How many members have joined the room.
    public let joinedMemberCount: Int
    /// How many unread events produce a notification.
    public let notificationCount: Int
    /// The subset of `notificationCount` that is a mention or a highlighted keyword.
    public let highlightCount: Int
    /// The current user's membership state in this room.
    public let membership: Membership

    public init(
        id: RoomID,
        displayName: String?,
        topic: String?,
        avatarURL: URL?,
        isDirect: Bool,
        isEncrypted: Bool?,
        joinedMemberCount: Int,
        notificationCount: Int,
        highlightCount: Int,
        membership: Membership
    ) {
        self.id = id
        self.displayName = displayName
        self.topic = topic
        self.avatarURL = avatarURL
        self.isDirect = isDirect
        self.isEncrypted = isEncrypted
        self.joinedMemberCount = joinedMemberCount
        self.notificationCount = notificationCount
        self.highlightCount = highlightCount
        self.membership = membership
    }

    /// True when the room has unread notifications or mentions.
    public var hasUnread: Bool { notificationCount > 0 || highlightCount > 0 }
}
