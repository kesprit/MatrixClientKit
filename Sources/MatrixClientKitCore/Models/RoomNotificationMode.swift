/// How much a room notifies the user.
public enum RoomNotificationMode: Sendable, Hashable {
    /// Every message notifies.
    case allMessages
    /// Only mentions and keywords notify.
    case mentionsAndKeywordsOnly
    /// Nothing notifies.
    case mute
}

/// A room's notification setting.
public struct RoomNotificationSettings: Sendable, Hashable {
    /// The mode in effect, whether the user chose it for this room or it comes from the account's
    /// defaults.
    public let mode: RoomNotificationMode
    /// True when the user has set nothing for this room, so the account's default applies.
    public let isDefault: Bool

    public init(mode: RoomNotificationMode, isDefault: Bool) {
        self.mode = mode
        self.isDefault = isDefault
    }
}
