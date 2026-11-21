import MatrixClientKitCore
import MatrixRustSDK
import Testing

@testable import MatrixClientKitRust

@Suite struct MessageKindMapperTests {
    private func event(
        readReceipts: [String: Receipt], profile: ProfileDetails
    ) -> EventTimelineItem {
        EventTimelineItem(
            isRemote: true, eventOrTransactionId: .eventId(eventId: "$e"), sender: "@a:e.org",
            senderProfile: profile, forwarder: nil, forwarderProfile: nil, isOwn: false,
            isEditable: false,
            content: .msgLike(
                content: MsgLikeContent(
                    kind: .message(
                        content: MessageContent(
                            msgType: .text(content: TextMessageContent(body: "hi", formatted: nil)),
                            body: "hi", isEdited: false, mentions: nil)),
                    reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil)),
            eventTypeRaw: "m.room.message", timestamp: 1_000, localSendState: nil,
            localCreatedAt: nil, readReceipts: readReceipts, origin: nil, canBeRepliedTo: true,
            lazyProvider: LazyTimelineItemProvider(noHandle: .init()))
    }

    @Test func messageExcludesOwnReceiptAndTakesAvatarFromSenderProfile() {
        let item = event(
            readReceipts: ["@me:e.org": Receipt(timestamp: 1), "@b:e.org": Receipt(timestamp: 2)],
            profile: .ready(
                displayName: "A", displayNameAmbiguous: false, avatarUrl: "mxc://e/a", status: nil,
                call: nil))
        let kind = TimelineMapper.kind(from: item, ownUserID: "@me:e.org")
        guard case let .message(message) = kind else {
            Issue.record("expected a message, got \(kind)")
            return
        }
        #expect(message.readReceipts.map(\.userID.rawValue) == ["@b:e.org"])
        #expect(message.senderAvatar?.url == "mxc://e/a")
        #expect(message.senderDisplayName == "A")
    }
}
