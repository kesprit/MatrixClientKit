import Foundation
import MatrixClientKitCore

/// Données d'exemple prêtes à l'emploi pour les tests et les aperçus.
public enum SampleData: Sendable {

    /// Construit un ``RoomSummary`` d'exemple, avec des valeurs par défaut raisonnables.
    public static func roomSummary(
        id: String = "!room:matrix.org",
        name: String = "Salon",
        unread: Int = 0
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
            membership: .joined
        )
    }

    /// Construit `count` rooms d'exemple, avec des identifiants et des noms distincts.
    public static func roomSummaries(count: Int) -> [RoomSummary] {
        (0..<count).map { index in
            roomSummary(id: "!room\(index):matrix.org", name: "Salon \(index)")
        }
    }

    /// Construit un ``TimelineItem`` d'exemple portant un message.
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
                    sender: UserID(rawValue: sender) ?? UserID(rawValue: "@inconnu:matrix.org")!,
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
}
