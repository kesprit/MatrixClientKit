import Foundation
import MatrixClientKitMocks
import Testing

@testable import MatrixClientKitCore

@Suite struct V06ServiceMockTests {
    private let alice: UserID
    private let bob: UserID

    init() throws {
        alice = try #require(UserID(rawValue: "@alice:example.org"))
        bob = try #require(UserID(rawValue: "@bob:example.org"))
    }

    // MARK: ProfileService

    @Test func profileReturnsConfiguredProfile() async throws {
        let mock = MockProfileService()
        let profile = SampleData.userProfile(userID: alice, displayName: "Alice")
        mock.profiles = [alice: profile]
        let service: any ProfileService = mock
        #expect(try await service.profile(of: alice) == profile)
    }

    @Test func unknownProfileThrowsNotFoundUser() async {
        let mock = MockProfileService()
        await #expect(throws: MatrixError.notFound(.user)) { try await mock.profile(of: bob) }
    }

    @Test func profileMutationsAreRecorded() async throws {
        let mock = MockProfileService()
        try await mock.setDisplayName("Alice")
        try await mock.setDisplayName("")
        try await mock.setAvatar(Data([1, 2]), mimeType: "image/png")
        try await mock.removeAvatar()
        try await mock.removeAvatar()
        try await mock.setPresence(.online)
        try await mock.setPresence(.offline)
        #expect(mock.displayNameChanges == ["Alice", ""])
        #expect(mock.avatarUploads == [.init(data: Data([1, 2]), mimeType: "image/png")])
        #expect(mock.removeAvatarCount == 2)
        #expect(mock.publishedPresences == [.online, .offline])
    }

    @Test func profileErrorFailsEveryCallAndStillRecords() async {
        let mock = MockProfileService()
        mock.error = .network(.offline)
        await #expect(throws: MatrixError.network(.offline)) { try await mock.profile(of: alice) }
        await #expect(throws: MatrixError.network(.offline)) { try await mock.setDisplayName("x") }
        await #expect(throws: MatrixError.network(.offline)) { try await mock.setAvatar(Data(), mimeType: "image/png") }
        await #expect(throws: MatrixError.network(.offline)) { try await mock.removeAvatar() }
        await #expect(throws: MatrixError.network(.offline)) { try await mock.setPresence(.unavailable) }
        #expect(mock.displayNameChanges == ["x"])
        #expect(mock.avatarUploads.count == 1)
        #expect(mock.removeAvatarCount == 1)
        // Upstream, a failing setPresence still applies the state (PRD §4.3).
        #expect(mock.publishedPresences == [.unavailable])
    }

    // MARK: AccountService

    @Test func managementURLReturnsConfiguredURLOrNil() async throws {
        let mock = MockAccountService()
        let url = try #require(URL(string: "https://account.example.org/devices"))
        mock.managementURLs = [.devices: url]
        #expect(try await mock.managementURL(for: .devices) == url)
        #expect(try await mock.managementURL(for: .profile) == nil)
        let device = try #require(DeviceID(rawValue: "ABC"))
        #expect(try await mock.managementURL(for: .device(device)) == nil)
    }

    @Test func ignoredUsersEmitsCurrentThenPushedSnapshots() async {
        let mock = MockAccountService()
        mock.emitIgnoredUsers([alice])
        var iterator = mock.ignoredUsers.makeAsyncIterator()
        #expect(await iterator.next() == [alice])
        mock.emitIgnoredUsers([alice, bob])
        #expect(await iterator.next() == [alice, bob])
    }

    @Test func ignoredUsersSubscriptionsAreIndependent() async {
        let mock = MockAccountService()
        var first = mock.ignoredUsers.makeAsyncIterator()
        var second = mock.ignoredUsers.makeAsyncIterator()
        #expect(await first.next() == [])
        #expect(await second.next() == [])
        mock.emitIgnoredUsers([bob])
        #expect(await first.next() == [bob])
        #expect(await second.next() == [bob])
    }

    @Test func ignoreAndUnignoreAreRecorded() async throws {
        let mock = MockAccountService()
        try await mock.ignore(alice)
        try await mock.ignore(bob)
        try await mock.unignore(alice)
        #expect(mock.ignoredCalls == [alice, bob])
        #expect(mock.unignoredCalls == [alice])
    }

    @Test func deactivateIsRecorded() async throws {
        let mock = MockAccountService()
        try await mock.deactivate(password: "secret", eraseData: true)
        #expect(mock.deactivations == [.init(password: "secret", eraseData: true)])
    }

    @Test func accountErrorFailsEveryCall() async throws {
        let mock = MockAccountService()
        mock.error = .server(.maintenance)
        await #expect(throws: MatrixError.server(.maintenance)) { try await mock.managementURL(for: .overview) }
        await #expect(throws: MatrixError.server(.maintenance)) { try await mock.ignore(alice) }
        await #expect(throws: MatrixError.server(.maintenance)) { try await mock.unignore(alice) }
        await #expect(throws: MatrixError.server(.maintenance)) {
            try await mock.deactivate(password: "p", eraseData: false)
        }
        #expect(mock.ignoredCalls == [alice])
        #expect(mock.unignoredCalls == [alice])
        #expect(mock.deactivations == [.init(password: "p", eraseData: false)])
    }

    @Test func deactivateErrorLeavesOtherCallsSucceeding() async throws {
        let mock = MockAccountService()
        let url = try #require(URL(string: "https://account.example.org/deactivate"))
        mock.managementURLs = [.deactivateAccount: url]
        mock.deactivateError = .authentication(.invalidCredentials)
        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            try await mock.deactivate(password: "wrong", eraseData: false)
        }
        #expect(try await mock.managementURL(for: .deactivateAccount) == url)
        try await mock.ignore(alice)
    }

    @Test(.timeLimit(.minutes(1)))
    func ignoredUsersStreamsCanBeFinished() async {
        let mock = MockAccountService()
        mock.emitIgnoredUsers([alice])
        let open = mock.ignoredUsers
        mock.finish()

        var received: [[UserID]] = []
        for await users in open { received.append(users) }
        #expect(received == [[alice]])

        // A subscription after finish() ends without any value: the failed initial read.
        var late: [[UserID]] = []
        for await users in mock.ignoredUsers { late.append(users) }
        #expect(late.isEmpty)
    }

    // MARK: SampleData

    @Test func sampleDataBuildsProfileReceiptAndMessageExtras() throws {
        let profile = SampleData.userProfile()
        #expect(profile.displayName != nil)
        let receipt = SampleData.readReceipt(userID: bob)
        #expect(receipt.userID == bob)
        let avatar = SampleData.mediaSource("a")
        let message = try #require(SampleData.message("hi", senderAvatar: avatar).message)
        #expect(message.senderAvatar == avatar)
        let plain = try #require(SampleData.message("hi").message)
        #expect(plain.senderAvatar == nil)
    }
}
