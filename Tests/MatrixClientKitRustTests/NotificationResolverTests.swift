import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let room = RoomID(rawValue: "!room:matrix.org")!
private let event = EventID(rawValue: "$event")!

private final class FakeNotificationClient: NotificationClientDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [(String, String)] = []
    var status: NotificationStatus = .eventNotFound
    var error: (any Error)?

    var requests: [(String, String)] { lock.withLock { _requests } }

    func getNotification(roomId: String, eventId: String) async throws -> NotificationStatus {
        try lock.withLock {
            _requests.append((roomId, eventId))
            if let error { throw error }
            return status
        }
    }
}

private func persistedSession() -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.example")!,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func theResolverAsksForTheEventAndMapsTheStatus() async throws {
    let client = FakeNotificationClient()
    client.status = .eventFilteredOut
    let resolver = RustNotificationResolver(notificationClient: client)

    let result = try await resolver.notification(roomID: room, eventID: event)

    #expect(result == .filteredOut)
    #expect(client.requests.count == 1)
    #expect(client.requests.first?.0 == "!room:matrix.org")
    #expect(client.requests.first?.1 == "$event")
}

@Test func anUpstreamFailureIsMapped() async {
    let client = FakeNotificationClient()
    client.error = ClientError.Generic(msg: "introuvable", details: nil)
    let resolver = RustNotificationResolver(notificationClient: client)

    await #expect(throws: MatrixError.unexpected(message: "introuvable", details: nil)) {
        try await resolver.notification(roomID: room, eventID: event)
    }
}

@Test func openingWithoutAStoredSessionReportsAMissingToken() async {
    let restorer = SessionRestorer(
        storage: .appGroup("group.com.example.app"),
        secureStore: InMemorySecureStore(),
        role: .notificationExtension
    )

    await #expect(throws: MatrixError.authentication(.missingToken)) {
        _ = try await restorer.makeNotificationResolver()
    }
}

@Test func anExtensionRefusesALocalStorageBeforeReadingTheSession() async throws {
    let restorer = SessionRestorer(
        storage: .local(directory: FileManager.default.temporaryDirectory),
        secureStore: InMemorySecureStore(),
        role: .notificationExtension
    )
    try restorer.persistence.save(persistedSession())

    await #expect(throws: MatrixError.storage(.unavailable)) {
        _ = try await restorer.makeNotificationResolver()
    }
}
