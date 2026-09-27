import Testing
import Foundation
import UserNotifications
import MatrixClientKit

private func notification(
    kind: MatrixNotification.Kind = .message(body: "Hello"),
    senderName: String? = "Alice",
    isDirect: Bool = false,
    isNoisy: Bool = true
) -> MatrixNotification {
    MatrixNotification(
        roomID: RoomID(rawValue: "!room:matrix.org")!,
        eventID: EventID(rawValue: "$event")!,
        sender: UserID(rawValue: "@alice:matrix.org")!,
        senderDisplayName: senderName,
        roomDisplayName: "Lounge",
        isDirect: isDirect,
        kind: kind,
        isNoisy: isNoisy,
        hasMention: false,
        threadID: nil
    )
}

@Test func aDirectMessageIsTitledWithTheSender() {
    let content = UNMutableNotificationContent()

    content.apply(notification(isDirect: true))

    #expect(content.title == "Alice")
    #expect(content.body == "Hello")
    #expect(content.threadIdentifier == "!room:matrix.org")
}

@Test func aGroupMessageIsTitledWithTheRoomAndPrefixedWithTheSender() {
    let content = UNMutableNotificationContent()

    content.apply(notification())

    #expect(content.title == "Lounge")
    #expect(content.body == "Alice: Hello")
}

@Test func anUnnamedSenderFallsBackToTheirIdentifier() {
    let content = UNMutableNotificationContent()

    content.apply(notification(senderName: nil, isDirect: true))

    #expect(content.title == "@alice:matrix.org")
}

@Test func anInvitationSaysSo() {
    let content = UNMutableNotificationContent()

    content.apply(notification(kind: .invite, isDirect: true))

    #expect(content.title == "Alice")
    #expect(content.body == "Invited you to chat")
}

@Test func onlyANoisyNotificationPlaysASound() {
    let noisy = UNMutableNotificationContent()
    let quiet = UNMutableNotificationContent()

    noisy.apply(notification(isNoisy: true))
    quiet.apply(notification(isNoisy: false))

    #expect(noisy.sound == .default)
    #expect(quiet.sound == nil)
}

@Test func theServiceRefusesALocalStorage() async {
    // Le refus a lieu avant toute lecture du Keychain : le cas ne dépend donc pas d'une session
    // qu'une autre exécution y aurait laissée.
    do {
        _ = try await MatrixNotificationService(storage: .local(directory: FileManager.default.temporaryDirectory))
        Issue.record("une extension ne doit pas pouvoir ouvrir un stockage local")
    } catch {
        #expect(error as? MatrixError == .storage(.unavailable))
    }
}
