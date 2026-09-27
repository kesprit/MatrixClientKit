import Testing
import Foundation
@testable import MatrixClientKitCore

// MARK: MatrixPushPayload

@Test func pushPayloadReadsTheRoomAndEventAtTheRoot() throws {
    let payload = try #require(
        MatrixPushPayload(userInfo: [
            "aps": ["mutable-content": 1],
            "room_id": "!room:matrix.org",
            "event_id": "$event",
            "unread_count": 2,
        ])
    )

    #expect(payload.roomID == RoomID(rawValue: "!room:matrix.org"))
    #expect(payload.eventID == EventID(rawValue: "$event"))
}

@Test func pushPayloadRejectsAMissingOrInvalidIdentifier() {
    let testCases: [[AnyHashable: Any]] = [
        ["event_id": "$event"],
        ["room_id": "!room:matrix.org"],
        ["room_id": "#alias:matrix.org", "event_id": "$event"],
        ["room_id": "!room:matrix.org", "event_id": ""],
        ["room_id": 42, "event_id": "$event"],
    ]

    for (index, userInfo) in testCases.enumerated() {
        #expect(MatrixPushPayload(userInfo: userInfo) == nil, "\(index)")
    }
}

// MARK: PusherConfiguration

private func configuration(token: [UInt8], fallbackAlert: String = "New message") -> PusherConfiguration {
    PusherConfiguration(
        deviceToken: Data(token),
        appID: "com.example.app.ios.prod",
        gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
        appDisplayName: "Example",
        deviceDisplayName: "iPhone",
        language: "en",
        fallbackAlert: fallbackAlert
    )
}

@Test func pushKeyIsTheTokenInBase64() {
    #expect(configuration(token: [0x00, 0x0F, 0xAB, 0xFF]).pushKey == "AA+r/w==")
}

@Test func pushKeyOfAnEmptyTokenIsEmpty() {
    #expect(configuration(token: []).pushKey.isEmpty)
}

@Test func defaultPayloadAsksForTheExtensionAndCarriesTheFallbackAlert() throws {
    let payload = try configuration(token: [1]).defaultPayload()

    #expect(payload == #"{"aps":{"alert":{"body":"New message"},"mutable-content":1}}"#)
}

@Test func defaultPayloadEscapesTheFallbackAlert() throws {
    let payload = try configuration(token: [1], fallbackAlert: #"Nouveau "message""#).defaultPayload()

    #expect(payload == #"{"aps":{"alert":{"body":"Nouveau \"message\""},"mutable-content":1}}"#)
}

@Test func languageDefaultsToALanguageCode() {
    let configuration = PusherConfiguration(
        deviceToken: Data([1]),
        appID: "com.example.app",
        gatewayURL: URL(string: "https://push.example.com/_matrix/push/v1/notify")!,
        appDisplayName: "Example",
        deviceDisplayName: "iPhone"
    )

    #expect(!configuration.language.isEmpty)
    #expect(!configuration.language.contains("_"))
    #expect(configuration.fallbackAlert == "New message")
}
