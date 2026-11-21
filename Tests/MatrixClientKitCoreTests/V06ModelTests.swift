import Foundation
import Testing

@testable import MatrixClientKitCore

@Suite struct V06ModelTests {
    private let alice: UserID
    private let bob: UserID

    init() throws {
        alice = try #require(UserID(rawValue: "@alice:example.org"))
        bob = try #require(UserID(rawValue: "@bob:example.org"))
    }

    @Test func readReceiptIsHashableByValue() {
        let date = Date(timeIntervalSince1970: 100)
        #expect(ReadReceipt(userID: alice, timestamp: date) == ReadReceipt(userID: alice, timestamp: date))
        #expect(ReadReceipt(userID: alice, timestamp: date) != ReadReceipt(userID: bob, timestamp: date))
        #expect(ReadReceipt(userID: alice, timestamp: nil) != ReadReceipt(userID: alice, timestamp: date))
        #expect(
            Set([ReadReceipt(userID: alice, timestamp: nil), ReadReceipt(userID: alice, timestamp: nil)]).count == 1)
    }

    @Test func readReceiptVisibilityCasesAreDistinct() {
        #expect(ReadReceiptVisibility.public != .private)
        #expect(Set([ReadReceiptVisibility.public, .private, .public]).count == 2)
    }

    @Test func userProfileIsHashableByValue() {
        let avatar = MediaSource(url: "mxc://example.org/a")
        let profile = UserProfile(userID: alice, displayName: "Alice", avatar: avatar)
        #expect(profile == UserProfile(userID: alice, displayName: "Alice", avatar: avatar))
        #expect(profile != UserProfile(userID: alice, displayName: nil, avatar: avatar))
        #expect(profile != UserProfile(userID: alice, displayName: "Alice", avatar: nil))
        #expect(profile.userID == alice)
        #expect(profile.displayName == "Alice")
        #expect(profile.avatar == avatar)
    }

    @Test func presenceCasesAreDistinct() {
        #expect(Set([Presence.online, .unavailable, .offline]).count == 3)
    }

    @Test func accountManagementActionsCompareByValue() throws {
        let device = try #require(DeviceID(rawValue: "ABC"))
        let other = try #require(DeviceID(rawValue: "XYZ"))
        #expect(AccountManagementAction.device(device) == .device(device))
        #expect(AccountManagementAction.device(device) != .device(other))
        #expect(AccountManagementAction.device(device) != .deleteDevice(device))
        #expect(AccountManagementAction.deleteDevice(device) == .deleteDevice(device))
        #expect(AccountManagementAction.overview != .profile)
        #expect(AccountManagementAction.devices != .deactivateAccount)
        #expect(
            Set([
                AccountManagementAction.overview, .profile, .devices, .deactivateAccount,
                .device(device), .device(device), .deleteDevice(device),
            ]).count == 6)
    }

    @Test func messageDefaultsNewFieldsAndKeepsExistingInitCall() {
        let message = Message(
            eventID: nil, sender: alice, senderDisplayName: nil, body: "hi",
            timestamp: Date(timeIntervalSince1970: 0), isOwn: false, isEdited: false,
            sendState: .sent)
        #expect(message.readReceipts.isEmpty)
        #expect(message.senderAvatar == nil)
    }

    @Test func messageCarriesReceiptsAndAvatar() {
        let receipt = ReadReceipt(userID: bob, timestamp: nil)
        let avatar = MediaSource(url: "mxc://example.org/a")
        let message = Message(
            eventID: nil, sender: alice, senderDisplayName: nil, body: "hi",
            timestamp: Date(timeIntervalSince1970: 0), isOwn: false, isEdited: false,
            sendState: .sent, readReceipts: [receipt], senderAvatar: avatar)
        #expect(message.readReceipts == [receipt])
        #expect(message.senderAvatar == avatar)
    }
}
