import Foundation
import MatrixClientKitCore
import MatrixRustSDK
import Testing

@testable import MatrixClientKitRust

@Suite struct ReceiptMapperTests {
    @Test func ownUserIsExcluded() {
        let receipts = ReceiptMapper.receipts(
            from: ["@me:e.org": Receipt(timestamp: 1), "@a:e.org": Receipt(timestamp: 2)],
            excluding: "@me:e.org")
        #expect(receipts.map(\.userID.rawValue) == ["@a:e.org"])
    }

    @Test func millisecondsBecomeDate() {
        let receipts = ReceiptMapper.receipts(
            from: ["@a:e.org": Receipt(timestamp: 1_500)], excluding: "@me:e.org")
        #expect(receipts.first?.timestamp == Date(timeIntervalSince1970: 1.5))
    }

    @Test func sortedMostRecentFirstThenByUserID() {
        let receipts = ReceiptMapper.receipts(
            from: [
                "@c:e.org": Receipt(timestamp: 10),
                "@b:e.org": Receipt(timestamp: 20),
                "@a:e.org": Receipt(timestamp: 20),
            ],
            excluding: "@me:e.org")
        #expect(receipts.map(\.userID.rawValue) == ["@a:e.org", "@b:e.org", "@c:e.org"])
    }

    @Test func missingTimestampComesLast() {
        let receipts = ReceiptMapper.receipts(
            from: ["@a:e.org": Receipt(timestamp: nil), "@z:e.org": Receipt(timestamp: 1)],
            excluding: "@me:e.org")
        #expect(receipts.map(\.userID.rawValue) == ["@z:e.org", "@a:e.org"])
        #expect(receipts.last?.timestamp == nil)
    }

    @Test func invalidUserIDIsDropped() {
        let receipts = ReceiptMapper.receipts(
            from: ["not-a-user": Receipt(timestamp: 1), "@a:e.org": Receipt(timestamp: 1)],
            excluding: "@me:e.org")
        #expect(receipts.map(\.userID.rawValue) == ["@a:e.org"])
    }

    @Test func emptyInputGivesEmptyList() {
        #expect(ReceiptMapper.receipts(from: [:], excluding: "@me:e.org").isEmpty)
    }
}

@Suite struct SenderAvatarMapperTests {
    private func ready(_ url: String?) -> ProfileDetails {
        .ready(
            displayName: nil, displayNameAmbiguous: false, avatarUrl: url, status: nil, call: nil)
    }

    @Test func readyProfileWithMxcUrlGivesSource() {
        #expect(TimelineMapper.senderAvatar(from: ready("mxc://e/a"))?.url == "mxc://e/a")
    }

    @Test func readyProfileWithoutAvatarGivesNil() {
        #expect(TimelineMapper.senderAvatar(from: ready(nil)) == nil)
    }

    @Test func nonMxcUrlGivesNil() {
        #expect(TimelineMapper.senderAvatar(from: ready("https://e.org/a.png")) == nil)
    }

    @Test func unresolvedProfilesGiveNil() {
        #expect(TimelineMapper.senderAvatar(from: .pending) == nil)
        #expect(TimelineMapper.senderAvatar(from: .unavailable) == nil)
        #expect(TimelineMapper.senderAvatar(from: .error(message: "x")) == nil)
    }
}
