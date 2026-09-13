import Foundation

/// État d'appartenance de l'utilisateur courant à une room.
public enum Membership: Sendable, Hashable {
    /// L'utilisateur courant est membre de la room.
    case joined
    /// L'utilisateur courant a été invité mais n'a pas encore rejoint la room.
    case invited
    /// L'utilisateur courant a quitté la room.
    case left
    /// L'utilisateur courant a demandé à rejoindre une room qui l'exige (knock).
    case knocked
    /// L'utilisateur courant a été banni de la room.
    case banned
}

/// Vue résumée d'une room, telle qu'affichée dans une liste.
public struct RoomSummary: Sendable, Hashable, Identifiable {
    /// Identifiant de la room.
    public let id: RoomID
    /// Nom d'affichage calculé de la room, s'il est disponible.
    public let displayName: String?
    /// Sujet de la room, s'il est défini.
    public let topic: String?
    /// URL de l'avatar de la room, s'il est défini.
    public let avatarURL: URL?
    /// Vrai s'il s'agit d'une conversation directe (DM) plutôt que d'une room de groupe.
    public let isDirect: Bool
    /// Vrai si la room est chiffrée de bout en bout.
    public let isEncrypted: Bool
    /// Nombre de membres ayant rejoint la room.
    public let joinedMemberCount: Int
    /// Nombre total d'événements non lus générant une notification.
    public let notificationCount: Int
    /// Sous-ensemble de `notificationCount` correspondant à une mention ou un mot-clé surligné.
    public let highlightCount: Int
    /// État d'appartenance de l'utilisateur courant à cette room.
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
