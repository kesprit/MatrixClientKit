import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let room = RoomID(rawValue: "!room:matrix.org")!
private let event = EventID(rawValue: "$event")!

private struct ContentFailure: Error {}

/// `TimelineEvent` est une classe FFI qu'un test ne peut pas construire ; son protocole, si.
private final class FakeTimelineEvent: TimelineEventProtocol, @unchecked Sendable {
    let result: Result<TimelineEventContent, any Error>
    let sender: String
    let thread: String?

    init(_ content: TimelineEventContent, sender: String = "@bob:matrix.org", thread: String? = nil) {
        self.result = .success(content)
        self.sender = sender
        self.thread = thread
    }

    init(failing sender: String = "@bob:matrix.org") {
        self.result = .failure(ContentFailure())
        self.sender = sender
        self.thread = nil
    }

    func content() throws -> TimelineEventContent { try result.get() }
    func eventId() -> String { "$event" }
    func senderId() -> String { sender }
    func threadRootEventId() -> String? { thread }
    func timestamp() -> Timestamp { 0 }
}

private func text(_ body: String) -> TimelineEventContent {
    .messageLike(
        content: .roomMessage(
            messageType: .text(content: TextMessageContent(body: body, formatted: nil)), inReplyToEventId: nil))
}

private func roomInfo(name: String = "Lounge", isDirect: Bool = false) -> NotificationRoomInfo {
    NotificationRoomInfo(
        displayName: name,
        avatarUrl: nil,
        canonicalAlias: nil,
        topic: nil,
        joinRule: nil,
        joinedMembersCount: 3,
        activeServiceMembersCount: 0,
        serviceMembers: [],
        isEncrypted: true,
        isDirect: isDirect,
        isSpace: false,
        isDm: isDirect
    )
}

private func map(
    _ source: NotificationEventSource,
    senderName: String? = "Bob",
    isNoisy: Bool? = true,
    hasMention: Bool? = false,
    threadID: String? = nil
) throws -> MatrixNotification {
    try NotificationMapper.notification(
        source: source,
        senderInfo: NotificationSenderInfo(displayName: senderName, avatarUrl: nil, isNameAmbiguous: false),
        roomInfo: roomInfo(),
        isNoisy: isNoisy,
        hasMention: hasMention,
        threadID: threadID,
        roomID: room,
        eventID: event
    )
}

// MARK: Statuts

@Test func statusesWithoutAnEventMapToTheirResult() throws {
    #expect(try NotificationMapper.result(from: .eventNotFound, roomID: room, eventID: event) == .notFound)
    #expect(try NotificationMapper.result(from: .eventFilteredOut, roomID: room, eventID: event) == .filteredOut)
    #expect(try NotificationMapper.result(from: .eventRedacted, roomID: room, eventID: event) == .redacted)
}

// MARK: Notification

@Test func aTextMessageCarriesItsSenderRoomAndBody() throws {
    let notification = try map(.timeline(FakeTimelineEvent(text("Salut"))))

    #expect(notification.roomID == room)
    #expect(notification.eventID == event)
    #expect(notification.sender == UserID(rawValue: "@bob:matrix.org"))
    #expect(notification.senderDisplayName == "Bob")
    #expect(notification.roomDisplayName == "Lounge")
    #expect(notification.isDirect == false)
    #expect(notification.kind == .message(body: "Salut"))
    #expect(notification.isNoisy)
    #expect(!notification.hasMention)
    #expect(notification.threadID == nil)
}

@Test func anInvitationNamesItsSender() throws {
    let notification = try map(.invite(sender: "@carol:matrix.org"))

    #expect(notification.kind == .invite)
    #expect(notification.sender == UserID(rawValue: "@carol:matrix.org"))
}

@Test func unknownNoiseAndMentionAreFalse() throws {
    let notification = try map(.timeline(FakeTimelineEvent(text("x"))), isNoisy: nil, hasMention: nil)

    #expect(!notification.isNoisy)
    #expect(!notification.hasMention)
}

@Test func theThreadComesFromTheItemThenFromTheEvent() throws {
    let fromItem = try map(.timeline(FakeTimelineEvent(text("x"), thread: "$other")), threadID: "$root")
    let fromEvent = try map(.timeline(FakeTimelineEvent(text("x"), thread: "$root")))

    #expect(fromItem.threadID == EventID(rawValue: "$root"))
    #expect(fromEvent.threadID == EventID(rawValue: "$root"))
}

@Test func anInvalidSenderIsAnUnexpectedErrorRatherThanACrash() {
    #expect(throws: MatrixError.self) {
        try map(.timeline(FakeTimelineEvent(text("x"), sender: "bob")))
    }
}

@Test func anEmoteUsesTheSenderIDWhenTheNameIsUnknown() throws {
    let emote = TimelineEventContent.messageLike(
        content: .roomMessage(
            messageType: .emote(content: EmoteMessageContent(body: "waves", formatted: nil)), inReplyToEventId: nil)
    )

    let notification = try map(.timeline(FakeTimelineEvent(emote)), senderName: nil)

    #expect(notification.kind == .message(body: "* @bob:matrix.org waves"))
}

@Test func unreadableContentFallsBackToAGenericBody() throws {
    let notification = try map(.timeline(FakeTimelineEvent(failing: "@bob:matrix.org")))

    #expect(notification.kind == .message(body: "Sent a message"))
}

// MARK: Corps

@Test func bodiesFollowTheSpecTable() {
    let notice = MessageType.notice(content: NoticeMessageContent(body: "Maintenance", formatted: nil))
    let location = MessageType.location(
        content: LocationContent(body: "Here", geoUri: "geo:0,0", description: nil, zoomLevel: nil, asset: .sender)
    )

    #expect(NotificationMapper.body(for: notice, senderName: "Bob") == "Maintenance")
    #expect(NotificationMapper.body(for: location, senderName: "Bob") == "Shared a location")
    #expect(
        NotificationMapper.body(for: .other(msgtype: "org.example", body: "Fallback"), senderName: "Bob") == "Fallback")
    #expect(
        NotificationMapper.body(for: .other(msgtype: "org.example", body: ""), senderName: "Bob") == "Sent a message")
}

@Test func anUndecryptableMessageUsesTheTimelinePhrase() {
    let body = NotificationMapper.body(for: .messageLike(content: .roomEncrypted), senderName: "Bob")

    #expect(body == TimelineMapper.undecryptableMessage)
    #expect(body == "The message could not be decrypted.")
}

@Test func otherEventsGetAGenericBody() {
    #expect(NotificationMapper.body(for: .messageLike(content: .sticker), senderName: "Bob") == "Sent a message")
}

@Test func aMediaBodyPrefersTheCaptionAndNeverTheFileName() {
    #expect(NotificationMapper.mediaBody(caption: "Sunset", fallback: "Sent an image") == "Sunset")
    #expect(NotificationMapper.mediaBody(caption: nil, fallback: "Sent an image") == "Sent an image")
    #expect(NotificationMapper.mediaBody(caption: "", fallback: "Sent an image") == "Sent an image")
}

// MARK: Paramètres et erreurs

@Test func modesMapBothWays() {
    let pairs: [(MatrixRustSDK.RoomNotificationMode, MatrixClientKitCore.RoomNotificationMode)] = [
        (.allMessages, .allMessages), (.mentionsAndKeywordsOnly, .mentionsAndKeywordsOnly), (.mute, .mute),
    ]
    for (upstream, domain) in pairs {
        #expect(NotificationMapper.mode(from: upstream) == domain)
        #expect(NotificationMapper.upstreamMode(from: domain) == upstream)
    }
}

@Test func settingsCarryTheDefaultFlag() {
    let settings = NotificationMapper.settings(
        from: MatrixRustSDK.RoomNotificationSettings(mode: .mute, isDefault: false))

    #expect(settings == MatrixClientKitCore.RoomNotificationSettings(mode: .mute, isDefault: false))
}

@Test func anInvalidRoomIsARoomNotFound() {
    #expect(NotificationMapper.error(from: NotificationSettingsError.InvalidRoomId(roomId: "!x")) == .notFound(.room))
}

@Test func otherSettingsErrorsGoThroughTheErrorMapper() {
    let mapped = NotificationMapper.error(from: ClientError.Generic(msg: "boom", details: nil))

    #expect(mapped == .unexpected(message: "boom", details: nil))
}
