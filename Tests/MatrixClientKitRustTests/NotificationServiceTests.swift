import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let room = RoomID(rawValue: "!room:matrix.org")!

private func configuration() -> PusherConfiguration {
    PusherConfiguration(
        deviceToken: Data([0xAB, 0x01]),
        appID: "com.example.app.ios.prod",
        gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
        appDisplayName: "Example",
        deviceDisplayName: "iPhone",
        language: "fr",
        fallbackAlert: "Nouveau message"
    )
}

private struct SetPusherCall: Equatable {
    let identifiers: PusherIdentifiers
    let kind: PusherKind
    let appDisplayName: String
    let deviceDisplayName: String
    let profileTag: String?
    let lang: String
    let append: Bool
}

private final class FakePushers: PusherDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _setCalls: [SetPusherCall] = []
    private var _deleted: [PusherIdentifiers] = []
    var error: (any Error)?

    var setCalls: [SetPusherCall] { lock.withLock { _setCalls } }
    var deleted: [PusherIdentifiers] { lock.withLock { _deleted } }

    func setPusher(
        identifiers: PusherIdentifiers,
        kind: PusherKind,
        appDisplayName: String,
        deviceDisplayName: String,
        profileTag: String?,
        lang: String,
        append: Bool
    ) async throws {
        try lock.withLock {
            if let error { throw error }
            _setCalls.append(
                SetPusherCall(
                    identifiers: identifiers, kind: kind, appDisplayName: appDisplayName,
                    deviceDisplayName: deviceDisplayName, profileTag: profileTag, lang: lang, append: append
                )
            )
        }
    }

    func deletePusher(identifiers: PusherIdentifiers) async throws {
        try lock.withLock {
            if let error { throw error }
            _deleted.append(identifiers)
        }
    }
}

private final class FakeSettings: NotificationSettingsDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _queries: [(String, Bool, Bool)] = []
    private var _modes: [(String, MatrixRustSDK.RoomNotificationMode)] = []
    private var _restored: [String] = []
    var current = MatrixRustSDK.RoomNotificationSettings(mode: .allMessages, isDefault: true)
    var error: (any Error)?

    var queries: [(String, Bool, Bool)] { lock.withLock { _queries } }
    var modes: [(String, MatrixRustSDK.RoomNotificationMode)] { lock.withLock { _modes } }
    var restored: [String] { lock.withLock { _restored } }

    func getRoomNotificationSettings(
        roomId: String,
        isEncrypted: Bool,
        isOneToOne: Bool
    ) async throws -> MatrixRustSDK.RoomNotificationSettings {
        try lock.withLock {
            if let error { throw error }
            _queries.append((roomId, isEncrypted, isOneToOne))
            return current
        }
    }

    func setRoomNotificationMode(roomId: String, mode: MatrixRustSDK.RoomNotificationMode) async throws {
        try lock.withLock {
            if let error { throw error }
            _modes.append((roomId, mode))
        }
    }

    func restoreDefaultRoomNotificationMode(roomId: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _restored.append(roomId)
        }
    }
}

private func makeService(
    pushers: FakePushers = FakePushers(),
    settings: FakeSettings = FakeSettings(),
    facts: RoomFacts? = RoomFacts(isEncrypted: true, isOneToOne: false)
) -> RustNotificationService {
    RustNotificationService(pushers: pushers, settings: settings, roomFacts: { _ in facts })
}

// MARK: Pusher

@Test func registeringSendsAnHTTPPusherInTheEventIDOnlyFormat() async throws {
    let pushers = FakePushers()
    let service = makeService(pushers: pushers)

    try await service.registerPusher(configuration())

    let expectedPayload = #"{"aps":{"alert":{"body":"Nouveau message"},"mutable-content":1}}"#
    #expect(
        pushers.setCalls == [
            SetPusherCall(
                identifiers: PusherIdentifiers(pushkey: "ab01", appId: "com.example.app.ios.prod"),
                kind: .http(
                    data: HttpPusherData(
                        url: "https://push.example.com/_matrix/push/v1/notify",
                        format: .eventIdOnly,
                        defaultPayload: expectedPayload
                    )
                ),
                appDisplayName: "Example",
                deviceDisplayName: "iPhone",
                profileTag: nil,
                lang: "fr",
                append: false
            )
        ]
    )
}

@Test func unregisteringDeletesThePusherForTheSameIdentifiers() async throws {
    let pushers = FakePushers()
    let service = makeService(pushers: pushers)

    try await service.unregisterPusher(configuration())

    #expect(pushers.deleted == [PusherIdentifiers(pushkey: "ab01", appId: "com.example.app.ios.prod")])
}

@Test func aPusherFailureIsMapped() async {
    let pushers = FakePushers()
    pushers.error = ClientError.Generic(msg: "refusé", details: nil)
    let service = makeService(pushers: pushers)

    await #expect(throws: MatrixError.unexpected(message: "refusé", details: nil)) {
        try await service.registerPusher(configuration())
    }
}

// MARK: Paramètres

@Test func readingSettingsPassesTheRoomFactsUpstream() async throws {
    let settings = FakeSettings()
    settings.current = MatrixRustSDK.RoomNotificationSettings(mode: .mentionsAndKeywordsOnly, isDefault: false)
    let service = makeService(settings: settings, facts: RoomFacts(isEncrypted: true, isOneToOne: true))

    let result = try await service.notificationSettings(for: room)

    #expect(result == MatrixClientKitCore.RoomNotificationSettings(mode: .mentionsAndKeywordsOnly, isDefault: false))
    #expect(settings.queries.count == 1)
    #expect(settings.queries.first?.0 == "!room:matrix.org")
    #expect(settings.queries.first?.1 == true)
    #expect(settings.queries.first?.2 == true)
}

@Test func anUnknownRoomIsARoomNotFound() async {
    let service = makeService(facts: nil)

    await #expect(throws: MatrixError.notFound(.room)) {
        try await service.notificationSettings(for: room)
    }
}

@Test func settingAModeSendsItUpstream() async throws {
    let settings = FakeSettings()
    let service = makeService(settings: settings)

    try await service.setNotificationMode(.mute, for: room)

    #expect(settings.modes.count == 1)
    #expect(settings.modes.first?.0 == "!room:matrix.org")
    #expect(settings.modes.first?.1 == .mute)
}

@Test func restoringTheDefaultSendsItUpstream() async throws {
    let settings = FakeSettings()
    let service = makeService(settings: settings)

    try await service.restoreDefaultNotificationMode(for: room)

    #expect(settings.restored == ["!room:matrix.org"])
}

@Test func anInvalidRoomFromTheSettingsIsARoomNotFound() async {
    let settings = FakeSettings()
    settings.error = NotificationSettingsError.InvalidRoomId(roomId: "!room:matrix.org")
    let service = makeService(settings: settings)

    await #expect(throws: MatrixError.notFound(.room)) {
        try await service.setNotificationMode(.mute, for: room)
    }
}
