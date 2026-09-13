import Testing
import Foundation
@testable import MatrixClientKitCore

private let roomID = RoomID(rawValue: "!room:matrix.org")!
private let alice = UserID(rawValue: "@alice:matrix.org")!

private func makeSummary(notifications: Int, highlights: Int) -> RoomSummary {
    RoomSummary(
        id: roomID,
        displayName: "Salon",
        topic: nil,
        avatarURL: nil,
        isDirect: false,
        isEncrypted: true,
        joinedMemberCount: 3,
        notificationCount: notifications,
        highlightCount: highlights,
        membership: .joined
    )
}

@Test func roomSummaryReportsUnreadActivity() {
    #expect(makeSummary(notifications: 0, highlights: 0).hasUnread == false)
    #expect(makeSummary(notifications: 2, highlights: 0).hasUnread)
    #expect(makeSummary(notifications: 0, highlights: 1).hasUnread)
}

@Test func roomSummaryIsIdentifiedByItsRoomID() {
    #expect(makeSummary(notifications: 0, highlights: 0).id == roomID)
}

@Test func sendStateDistinguishesFailure() {
    #expect(SendState.failed(reason: "réseau", isRecoverable: true).isFailed)
    #expect(SendState.sending.isFailed == false)
    #expect(SendState.sent.isFailed == false)

    // `isRecoverableFailure` répond à la question qu'une interface pose réellement : proposer
    // « réessayer », ou demander à l'utilisateur de résoudre le problème d'abord.
    #expect(SendState.failed(reason: "réseau", isRecoverable: true).isRecoverableFailure)
    let unrecoverable = SendState.failed(reason: "session non vérifiée", isRecoverable: false)
    #expect(unrecoverable.isRecoverableFailure == false)
    #expect(SendState.sent.isRecoverableFailure == false)
}

@Test func messageContentExposesPlainBody() {
    #expect(MessageContent.text("bonjour").plainBody == "bonjour")
    #expect(MessageContent.markdown("**gras**").plainBody == "**gras**")
}

@Test func timelineItemExposesItsMessageWhenPresent() {
    let message = Message(
        eventID: EventID(rawValue: "$abc"),
        sender: alice,
        senderDisplayName: "Alice",
        body: "bonjour",
        timestamp: Date(timeIntervalSince1970: 1_000),
        isOwn: false,
        isEdited: false,
        sendState: .sent
    )
    let item = TimelineItem(id: "1", kind: .message(message))
    #expect(item.message?.body == "bonjour")

    let separator = TimelineItem(id: "2", kind: .dateSeparator(Date(timeIntervalSince1970: 0)))
    #expect(separator.message == nil)
}

@Test func sessionDataRoundTripsThroughJSON() throws {
    let data = MatrixSessionData(
        userID: alice,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!,
        accessToken: "token",
        refreshToken: "refresh",
        oauthData: nil,
        slidingSyncVersion: "native"
    )
    let encoded = try JSONEncoder().encode(data)
    let decoded = try JSONDecoder().decode(MatrixSessionData.self, from: encoded)
    #expect(decoded == data)
}

@Test func sessionDataDescriptionRedactsTokens() {
    let data = MatrixSessionData(
        userID: alice,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!,
        accessToken: "secret-access-token",
        refreshToken: "secret-refresh-token",
        oauthData: nil,
        slidingSyncVersion: "native"
    )
    #expect(data.description.contains("secret-access-token") == false)
    #expect(data.description.contains("secret-refresh-token") == false)
    #expect(data.debugDescription.contains("secret-access-token") == false)
    #expect(data.debugDescription.contains("secret-refresh-token") == false)
}

@Test func credentialsDescriptionRedactsPassword() {
    let credentials = Credentials.password(
        username: "alice",
        password: "hunter2",
        deviceName: "iPhone"
    )
    #expect(credentials.description.contains("hunter2") == false)
    #expect(credentials.debugDescription.contains("hunter2") == false)
    #expect(credentials.description.contains("alice"))
}
