import Testing
import Foundation
import MatrixClientKitCore
import MatrixClientKitMocks

private let room = RoomID(rawValue: "!room:matrix.org")!
private let event = EventID(rawValue: "$event")!

@Test func mockNotificationServiceRecordsPushers() async throws {
    let service = MockNotificationService()
    let configuration = SampleData.pusherConfiguration()

    try await service.registerPusher(configuration)
    try await service.unregisterPusher(configuration)

    #expect(service.registeredPushers == [configuration])
    #expect(service.unregisteredPushers == [configuration])
}

@Test func mockNotificationServiceStartsFromTheDefaultSettings() async throws {
    let service = MockNotificationService()

    let settings = try await service.notificationSettings(for: room)

    #expect(settings == RoomNotificationSettings(mode: .allMessages, isDefault: true))
}

@Test func mockNotificationServiceAppliesAndRestoresAMode() async throws {
    let service = MockNotificationService()

    try await service.setNotificationMode(.mute, for: room)
    let muteSettings = try await service.notificationSettings(for: room)
    #expect(muteSettings == RoomNotificationSettings(mode: .mute, isDefault: false))

    try await service.restoreDefaultNotificationMode(for: room)
    let restoredSettings = try await service.notificationSettings(for: room)
    #expect(restoredSettings == service.defaultSettings)
}

@Test func mockNotificationServiceFailsEachOperationOnDemand() async {
    let service = MockNotificationService()
    service.registerError = .network(.offline)
    service.settingsError = .notFound(.room)

    await #expect(throws: MatrixError.network(.offline)) {
        try await service.registerPusher(SampleData.pusherConfiguration())
    }
    await #expect(throws: MatrixError.notFound(.room)) {
        try await service.setNotificationMode(.mute, for: room)
    }
    #expect(service.registeredPushers.isEmpty)
}

@Test func mockResolverReturnsTheResultSetForAnEvent() async throws {
    let resolver = MockNotificationResolver()
    let notification = SampleData.notification()
    resolver.setResult(.notification(notification), roomID: room, eventID: event)

    let result = try await resolver.notification(roomID: room, eventID: event)

    #expect(result == .notification(notification))
    #expect(resolver.requests == [MatrixPushPayload(roomID: room, eventID: event)])
}

@Test func mockResolverFallsBackToTheDefaultResult() async throws {
    let resolver = MockNotificationResolver()
    resolver.defaultResult = .filteredOut

    #expect(try await resolver.notification(roomID: room, eventID: event) == .filteredOut)
}

@Test func mockResolverThrowsTheInjectedError() async {
    let resolver = MockNotificationResolver()
    resolver.error = .authentication(.missingToken)

    await #expect(throws: MatrixError.authentication(.missingToken)) {
        try await resolver.notification(roomID: room, eventID: event)
    }
    #expect(resolver.requests.count == 1)
}
