/// A notification resolved from a push, ready to be displayed.
public struct MatrixNotification: Sendable, Hashable {
    /// What the notification is about.
    public enum Kind: Sendable, Hashable {
        /// A message, with its text as it should appear in the notification.
        case message(body: String)
        /// An invitation to join the room.
        case invite
    }

    public let roomID: RoomID
    public let eventID: EventID
    /// Who sent the message or the invitation.
    public let sender: UserID
    /// The sender's display name, when known.
    public let senderDisplayName: String?
    /// The room's display name.
    public let roomDisplayName: String
    /// True for a direct conversation.
    public let isDirect: Bool
    public let kind: Kind
    /// True when the user's push rules ask for a sound.
    public let isNoisy: Bool
    /// True when the message mentions the user.
    public let hasMention: Bool
    /// The thread the message belongs to, if any.
    public let threadID: EventID?

    public init(
        roomID: RoomID,
        eventID: EventID,
        sender: UserID,
        senderDisplayName: String?,
        roomDisplayName: String,
        isDirect: Bool,
        kind: Kind,
        isNoisy: Bool,
        hasMention: Bool,
        threadID: EventID?
    ) {
        self.roomID = roomID
        self.eventID = eventID
        self.sender = sender
        self.senderDisplayName = senderDisplayName
        self.roomDisplayName = roomDisplayName
        self.isDirect = isDirect
        self.kind = kind
        self.isNoisy = isNoisy
        self.hasMention = hasMention
        self.threadID = threadID
    }
}

/// The outcome of resolving a push.
public enum NotificationResult: Sendable, Hashable {
    /// The event was found: display it.
    case notification(MatrixNotification)
    /// The event could not be found. Displaying the push's original content is a reasonable
    /// fallback.
    case notFound
    /// The user's push rules, or an ignored sender, rule the event out: display nothing.
    ///
    /// Hiding a notification by delivering empty content requires the extension to have the
    /// `com.apple.developer.usernotifications.filtering` entitlement. Without it, deliver the
    /// original content or a generic one.
    case filteredOut
    /// The event was deleted: display nothing.
    ///
    /// Hiding a notification by delivering empty content requires the extension to have the
    /// `com.apple.developer.usernotifications.filtering` entitlement. Without it, deliver the
    /// original content or a generic one.
    case redacted
}
