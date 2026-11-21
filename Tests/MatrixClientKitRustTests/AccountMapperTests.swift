import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

@Suite struct AccountMapperTests {
    private let device = DeviceID(rawValue: "ABCDEF")!

    @Test func overviewHasNoUpstreamAction() {
        #expect(AccountMapper.upstreamAction(for: .overview) == nil)
    }

    @Test func eachActionMapsToItsUpstreamCounterpart() {
        #expect(AccountMapper.upstreamAction(for: .profile) == .profile)
        #expect(AccountMapper.upstreamAction(for: .devices) == .devicesList)
        #expect(AccountMapper.upstreamAction(for: .device(device)) == .deviceView(deviceId: "ABCDEF"))
        #expect(AccountMapper.upstreamAction(for: .deleteDevice(device)) == .deviceDelete(deviceId: "ABCDEF"))
        #expect(AccountMapper.upstreamAction(for: .deactivateAccount) == .accountDeactivate)
    }

    @Test func validURLIsParsed() throws {
        let url = try AccountMapper.managementURL(from: "https://account.example.org/?action=profile")
        #expect(url == URL(string: "https://account.example.org/?action=profile"))
    }

    @Test func nilStaysNil() throws {
        #expect(try AccountMapper.managementURL(from: nil) == nil)
    }

    @Test func malformedURLIsUnexpected() {
        #expect(throws: MatrixError.self) { try AccountMapper.managementURL(from: "not a url with spaces") }
        #expect(throws: MatrixError.self) { try AccountMapper.managementURL(from: "") }
    }

    @Test func ignoredUsersDropsMalformedIdentifiers() {
        let users = AccountMapper.userIDs(from: ["@a:x.org", "garbage", "@b:x.org"])
        #expect(users.map(\.rawValue) == ["@a:x.org", "@b:x.org"])
    }
}
