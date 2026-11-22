import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Testing

@testable import MatrixClientKitRust

@Suite struct MessageKindMapperTests {
    private static let own = "@me:e.org"
    private static let upstreamReceipts: [String: Receipt] = [
        own: Receipt(timestamp: 1), "@b:e.org": Receipt(timestamp: 2),
        "@a:e.org": Receipt(timestamp: 2), "@c:e.org": Receipt(timestamp: 9),
    ]
    /// Ordre du §4.1 : horodatage décroissant, puis `UserID`.
    private static let expectedReceipts = ["@c:e.org", "@a:e.org", "@b:e.org"]

    private func messageContent(_ body: String = "hi") -> TimelineItemContent {
        .msgLike(
            content: MsgLikeContent(
                kind: .message(
                    content: MessageContent(
                        msgType: .text(content: TextMessageContent(body: body, formatted: nil)),
                        body: body, isEdited: false, mentions: nil)),
                reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil))
    }

    private func msgLike(_ kind: MsgLikeKind) -> TimelineItemContent {
        .msgLike(
            content: MsgLikeContent(
                kind: kind, reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil))
    }

    private func event(
        content: TimelineItemContent? = nil,
        sender: String = "@a:e.org",
        readReceipts: [String: Receipt] = [:],
        profile: ProfileDetails = .pending
    ) -> EventTimelineItem {
        EventTimelineItem(
            isRemote: true, eventOrTransactionId: .eventId(eventId: "$e"), sender: sender,
            senderProfile: profile, forwarder: nil, forwarderProfile: nil, isOwn: false,
            isEditable: false, content: content ?? messageContent(),
            eventTypeRaw: "m.room.message", timestamp: 1_000, localSendState: nil,
            localCreatedAt: nil, readReceipts: readReceipts, origin: nil, canBeRepliedTo: true,
            lazyProvider: LazyTimelineItemProvider(noHandle: .init()))
    }

    private func item(_ event: EventTimelineItem) -> MatrixClientKitCore.TimelineItem {
        TimelineMapper.item(id: "id", event: event, ownUserID: Self.own)
    }

    /// Mappe `content` avec les accusés amont et vérifie qu'ils sont tous conservés, hors le nôtre.
    private func mappedKeepingReceipts(
        _ content: TimelineItemContent, sender: String = "@a:e.org",
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> MatrixClientKitCore.TimelineItem {
        let mapped = item(
            event(content: content, sender: sender, readReceipts: Self.upstreamReceipts))
        #expect(
            mapped.readReceipts.map(\.userID.rawValue) == Self.expectedReceipts,
            sourceLocation: sourceLocation)
        return mapped
    }

    private func expectUnsupported(
        _ mapped: MatrixClientKitCore.TimelineItem, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .unsupported = mapped.kind else {
            Issue.record("expected .unsupported, got \(mapped.kind)", sourceLocation: sourceLocation)
            return
        }
    }

    // MARK: Accusés conservés quel que soit le Kind

    @Test func messageKeepsReceiptsExcludingOwnAndSorted() {
        #expect(mappedKeepingReceipts(messageContent()).message != nil)
    }

    @Test func stateEventKeepsReceipts() {
        expectUnsupported(mappedKeepingReceipts(.state(stateKey: "", content: .roomName(name: "n"))))
    }

    @Test func redactedKeepsReceipts() {
        #expect(mappedKeepingReceipts(msgLike(.redacted)).kind == .redacted)
    }

    @Test func unableToDecryptKeepsReceipts() {
        let mapped = mappedKeepingReceipts(msgLike(.unableToDecrypt(msg: .unknown)))
        guard case .unableToDecrypt = mapped.kind else {
            Issue.record("expected .unableToDecrypt, got \(mapped.kind)")
            return
        }
    }

    @Test func stickerKeepsReceipts() throws {
        let info = ImageInfo(
            height: nil, width: nil, mimetype: nil, size: nil, thumbnailInfo: nil,
            thumbnailSource: nil, blurhash: nil, isAnimated: nil)
        let source = try MatrixRustSDK.MediaSource.fromUrl(url: "mxc://e/s")
        expectUnsupported(
            mappedKeepingReceipts(msgLike(.sticker(body: "s", info: info, source: source))))
    }

    @Test func pollKeepsReceipts() {
        expectUnsupported(
            mappedKeepingReceipts(
                msgLike(
                    .poll(
                        question: "q", kind: .disclosed, maxSelections: 1,
                        answers: [PollAnswer(id: "1", text: "a")], votes: [:], endTime: nil,
                        hasBeenEdited: false))))
    }

    @Test func invalidSenderKeepsReceipts() {
        expectUnsupported(mappedKeepingReceipts(messageContent(), sender: "not a user id"))
    }

    @Test func ownReceiptAloneYieldsNoReceipts() {
        let mapped = item(event(readReceipts: [Self.own: Receipt(timestamp: 1)]))
        #expect(mapped.readReceipts.isEmpty)
    }

    // MARK: Items virtuels

    @Test func virtualItemsHaveNoReceipts() {
        #expect(TimelineMapper.item(id: "d", virtual: .dateDivider(ts: 1_000)).readReceipts.isEmpty)
        #expect(TimelineMapper.item(id: "r", virtual: .readMarker).readReceipts.isEmpty)
        #expect(TimelineMapper.item(id: "s", virtual: .timelineStart).readReceipts.isEmpty)
    }

    // MARK: Hashable

    @Test func itemsWithDifferentReceiptsAreDifferent() throws {
        let alice = ReadReceipt(userID: try #require(UserID(rawValue: "@a:e.org")), timestamp: nil)
        let bare = MatrixClientKitCore.TimelineItem(id: "x", kind: .readMarker)
        let read = MatrixClientKitCore.TimelineItem(id: "x", kind: .readMarker, readReceipts: [alice])
        #expect(bare != read)
        #expect(Set([bare, read]).count == 2)
    }

    // MARK: Avatar de l'expéditeur

    @Test func messageTakesAvatarAndNameFromSenderProfile() {
        let kind = TimelineMapper.kind(
            from: event(
                profile: .ready(
                    displayName: "A", displayNameAmbiguous: false, avatarUrl: "mxc://e/a",
                    status: nil, call: nil)))
        guard case let .message(message) = kind else {
            Issue.record("expected a message, got \(kind)")
            return
        }
        #expect(message.senderAvatar?.url == "mxc://e/a")
        #expect(message.senderDisplayName == "A")
    }
}
