import Foundation

/// Who can see a read receipt you send.
public enum ReadReceiptVisibility: Sendable, Hashable {
    /// Every member of the room (`m.read`).
    case `public`
    /// Only your own devices (`m.read.private`): your unread counts stay in sync, nobody else
    /// learns that you read the room.
    case `private`
}

/// Another member's read position: the latest message they read.
///
/// A receipt appears only on the *latest* message a member read. To know whether a member read
/// a message `M`, look for their receipt on `M` or on any more recent message.
public struct ReadReceipt: Sendable, Hashable {
    /// The member who read the message.
    public let userID: UserID
    /// When they read it, when the homeserver says.
    public let timestamp: Date?

    /// Creates a read receipt.
    public init(userID: UserID, timestamp: Date?) {
        self.userID = userID
        self.timestamp = timestamp
    }
}
