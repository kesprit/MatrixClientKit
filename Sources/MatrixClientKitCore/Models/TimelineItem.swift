import Foundation

/// The delivery state of a message sent from this device.
public enum SendState: Sendable, Hashable {
    /// The message is on its way to the homeserver.
    case sending
    /// The homeserver accepted the message.
    case sent
    /// Sending failed; `reason` describes why.
    ///
    /// - Parameters:
    ///   - reason: why it failed, written to be readable. Diagnostic: an application that
    ///     localises its interface should produce its own copy rather than showing this string.
    ///   - isRecoverable: the send can be retried **as is**, typically once connectivity comes
    ///     back, as opposed to a failure the user must resolve first (verify their session,
    ///     remove an unverified device, pick another attachment). This is the distinction an
    ///     interface uses to decide between offering "retry" and "discard".
    case failed(reason: String, isRecoverable: Bool)

    /// True when sending failed.
    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// True when sending failed and can be retried as is; `false` in every other case, including
    /// when sending did not fail.
    public var isRecoverableFailure: Bool {
        if case let .failed(_, isRecoverable) = self { return isRecoverable }
        return false
    }
}

/// A message that can be displayed in a timeline.
public struct Message: Sendable, Hashable {
    /// The event identifier once the homeserver accepted it; `nil` while the message is local.
    public let eventID: EventID?
    /// The sender's identifier.
    public let sender: UserID
    /// The sender's display name at the time of sending, when known.
    public let senderDisplayName: String?
    /// The message's text body.
    public let body: String
    /// When the message was sent.
    public let timestamp: Date
    /// True when the current user sent the message.
    public let isOwn: Bool
    /// True when the message was edited after it was first sent.
    public let isEdited: Bool
    /// The message's delivery state.
    public let sendState: SendState

    public init(
        eventID: EventID?,
        sender: UserID,
        senderDisplayName: String?,
        body: String,
        timestamp: Date,
        isOwn: Bool,
        isEdited: Bool,
        sendState: SendState
    ) {
        self.eventID = eventID
        self.sender = sender
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.timestamp = timestamp
        self.isOwn = isOwn
        self.isEdited = isEdited
        self.sendState = sendState
    }
}

/// An item in a timeline: a message, a marker, or an event v0.1 does not handle.
public struct TimelineItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A message to display.
        case message(Message)
        /// An event whose content was removed, by moderation or by its author.
        case redacted
        /// An encrypted event the client could not decrypt; `reason` says why.
        case unableToDecrypt(reason: String)
        /// A visual separator marking a change of day.
        case dateSeparator(Date)
        /// The current user's read marker for this room.
        case readMarker
        /// An event of a recognised type that v0.1 does not render.
        case unsupported(description: String)
    }

    /// The item's stable identity within the timeline, used to diff a displayed list. This is
    /// not a Matrix event identifier: an item with no associated event — a separator, a read
    /// marker — still has one.
    public let id: String
    /// What the item holds.
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// The message this item carries, when it is a message.
    public var message: Message? {
        if case let .message(message) = kind { return message }
        return nil
    }
}
