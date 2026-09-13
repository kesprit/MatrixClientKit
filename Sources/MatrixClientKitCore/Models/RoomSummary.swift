import Foundation

/// État d'appartenance de l'utilisateur courant à une room.
public enum Membership: Sendable, Hashable {
    case joined
    case invited
    case left
    case knocked
    case banned
}

/// Vue résumée d'une room, telle qu'affichée dans une liste.
public struct RoomSummary: Sendable, Hashable, Identifiable {
    public let id: RoomID
    public let displayName: String?
    public let topic: String?
    public let avatarURL: URL?
    public let isDirect: Bool
    public let isEncrypted: Bool
    public let joinedMemberCount: Int
    public let notificationCount: Int
    public let highlightCount: Int
    public let membership: Membership

    public init(
        id: RoomID,
        displayName: String?,
        topic: String?,
        avatarURL: URL?,
        isDirect: Bool,
        isEncrypted: Bool,
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

    /// Vrai si la room comporte des notifications ou des mentions non lues.
    public var hasUnread: Bool { notificationCount > 0 || highlightCount > 0 }
}
