import Foundation
import MatrixClientKitCore

/// Ready-made sample data for tests and previews.
public enum SampleData: Sendable {

    /// Builds a sample ``RoomSummary`` with sensible defaults.
    ///
    /// - Parameter membership: defaults to ``Membership/joined``. Pass another value to build a
    ///   list that a filter can meaningfully narrow — a test asserting that invitations stay out
    ///   of the main list needs at least one room that is not joined.
    public static func roomSummary(
        id: String = "!room:matrix.org",
        name: String = "Lounge",
        unread: Int = 0,
        membership: Membership = .joined
    ) -> RoomSummary {
        RoomSummary(
            id: RoomID(rawValue: id) ?? RoomID(rawValue: "!fallback:matrix.org")!,
            displayName: name,
            topic: nil,
            avatarURL: nil,
            isDirect: false,
            isEncrypted: true,
            joinedMemberCount: 4,
            notificationCount: unread,
            highlightCount: 0,
            membership: membership
        )
    }

    /// Builds `count` sample rooms with distinct identifiers and names.
    public static func roomSummaries(
        count: Int,
        membership: Membership = .joined
    ) -> [RoomSummary] {
        (0..<count).map { index in
            roomSummary(id: "!room\(index):matrix.org", name: "Lounge \(index)", membership: membership)
        }
    }

    /// Builds a sample ``TimelineItem`` carrying a message.
    public static func message(
        _ body: String,
        from sender: String = "@alice:matrix.org",
        isOwn: Bool = false
    ) -> TimelineItem {
        TimelineItem(
            id: UUID().uuidString,
            kind: .message(
                Message(
                    eventID: EventID(rawValue: "$\(UUID().uuidString)"),
                    sender: UserID(rawValue: sender) ?? UserID(rawValue: "@unknown:matrix.org")!,
                    senderDisplayName: nil,
                    body: body,
                    timestamp: Date(),
                    isOwn: isOwn,
                    isEdited: false,
                    sendState: .sent
                )
            )
        )
    }

    /// Builds a sample ``MatrixNotification`` from Alice in the "Lounge" room.
    public static func notification(
        kind: MatrixNotification.Kind = .message(body: "Hello"),
        isDirect: Bool = false,
        isNoisy: Bool = true
    ) -> MatrixNotification {
        MatrixNotification(
            roomID: RoomID(rawValue: "!room:matrix.org")!,
            eventID: EventID(rawValue: "$event")!,
            sender: UserID(rawValue: "@alice:matrix.org")!,
            senderDisplayName: "Alice",
            roomDisplayName: "Lounge",
            isDirect: isDirect,
            kind: kind,
            isNoisy: isNoisy,
            hasMention: false,
            threadID: nil
        )
    }

    /// Builds a sample ``PusherConfiguration`` pointing at a gateway on `example.com`.
    public static func pusherConfiguration() -> PusherConfiguration {
        PusherConfiguration(
            deviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            appID: "com.example.app.ios.dev",
            gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
            appDisplayName: "Example",
            deviceDisplayName: "iPhone",
            language: "en"
        )
    }
}
