import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private struct AvatarCall: Equatable {
    let mimeType: String
    let data: Data
}

private struct PresenceCall: Equatable {
    let presence: PresenceState
    let immediate: Bool
}

private final class FakeProfileDriver: ProfileDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var _profileRequests: [String] = []
    private var _names: [String] = []
    private var _avatars: [AvatarCall] = []
    private var _removals = 0
    private var _presences: [PresenceCall] = []
    var error: (any Error)?
    var profile = MatrixRustSDK.UserProfile(
        userId: "@alice:example.org", displayName: "Alice", avatarUrl: "mxc://example.org/a",
        status: nil, call: nil)

    var profileRequests: [String] { lock.withLock { _profileRequests } }
    var names: [String] { lock.withLock { _names } }
    var avatars: [AvatarCall] { lock.withLock { _avatars } }
    var removals: Int { lock.withLock { _removals } }
    var presences: [PresenceCall] { lock.withLock { _presences } }

    func getProfile(userId: String) async throws -> MatrixRustSDK.UserProfile {
        try lock.withLock {
            if let error { throw error }
            _profileRequests.append(userId)
        }
        return profile
    }

    func setDisplayName(name: String) async throws {
        try lock.withLock {
            if let error { throw error }
            _names.append(name)
        }
    }

    func uploadAvatar(mimeType: String, data: Data) async throws {
        try lock.withLock {
            if let error { throw error }
            _avatars.append(AvatarCall(mimeType: mimeType, data: data))
        }
    }

    func removeAvatar() async throws {
        try lock.withLock {
            if let error { throw error }
            _removals += 1
        }
    }

    func setPresence(presence: PresenceState, immediate: Bool) async throws {
        try lock.withLock {
            if let error { throw error }
            _presences.append(PresenceCall(presence: presence, immediate: immediate))
        }
    }
}

private func apiError(_ kind: ErrorKind, code: String = "M_X", details: String? = nil) -> ClientError {
    .MatrixApi(kind: kind, code: code, msg: "boom", details: details)
}

private let alice = UserID(rawValue: "@alice:example.org")!

@Suite struct ProfileServiceTests {
    private func makeService(_ driver: FakeProfileDriver) -> RustProfileService {
        RustProfileService(driver: driver, lifetime: .detached())
    }

    @Test func profileRequestsTheRawUserID() async throws {
        let driver = FakeProfileDriver()
        let profile = try await makeService(driver).profile(of: alice)
        #expect(driver.profileRequests == ["@alice:example.org"])
        #expect(profile.userID == alice)
        #expect(profile.displayName == "Alice")
        #expect(profile.avatar?.url == "mxc://example.org/a")
    }

    @Test func profileWithoutNameOrAvatar() async throws {
        let driver = FakeProfileDriver()
        driver.profile = MatrixRustSDK.UserProfile(
            userId: "@alice:example.org", displayName: nil, avatarUrl: nil, status: nil, call: nil)
        let profile = try await makeService(driver).profile(of: alice)
        #expect(profile.displayName == nil)
        #expect(profile.avatar == nil)
    }

    @Test func nonMxcAvatarBecomesNil() async throws {
        let driver = FakeProfileDriver()
        driver.profile = MatrixRustSDK.UserProfile(
            userId: "@alice:example.org", displayName: "Alice", avatarUrl: "https://example.org/a.png",
            status: nil, call: nil)
        let profile = try await makeService(driver).profile(of: alice)
        #expect(profile.avatar == nil)
        #expect(profile.displayName == "Alice")
    }

    @Test func invalidUpstreamUserIDIsUnexpected() async {
        let driver = FakeProfileDriver()
        driver.profile = MatrixRustSDK.UserProfile(
            userId: "not-a-user-id", displayName: nil, avatarUrl: nil, status: nil, call: nil)
        let service = makeService(driver)
        await #expect(
            throws: MatrixError.unexpected(message: "The server returned an invalid user ID.", details: "not-a-user-id")
        ) { try await service.profile(of: alice) }
    }

    @Test func unknownUserBecomesNotFoundUser() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.notFound)
        let service = makeService(driver)
        await #expect(throws: MatrixError.notFound(.user)) { try await service.profile(of: alice) }
    }

    /// Synapse répond 404 `M_UNKNOWN` (et non `M_NOT_FOUND`) pour un profil inconnu : erreur
    /// relevée telle quelle contre le harnais.
    @Test func synapse404MUnknownBecomesNotFoundUser() async {
        let driver = FakeProfileDriver()
        driver.error = ClientError.MatrixApi(
            kind: .unknown, code: "M_UNKNOWN", msg: "No row found (profiles)",
            details: "Error { status_code: 404, headers: {}, body: Json(Object {}), kind: Unknown }")
        let service = makeService(driver)
        await #expect(throws: MatrixError.notFound(.user)) { try await service.profile(of: alice) }
    }

    @Test func mUnknownWithAnotherStatusIsNotRemapped() async {
        let driver = FakeProfileDriver()
        driver.error = ClientError.MatrixApi(
            kind: .unknown, code: "M_UNKNOWN", msg: "boom",
            details: "Error { status_code: 500, headers: {}, kind: Unknown }")
        let service = makeService(driver)
        await #expect(
            throws: MatrixError.unexpected(
                message: "boom", details: "M_UNKNOWN: Error { status_code: 500, headers: {}, kind: Unknown }")
        ) { try await service.profile(of: alice) }
    }

    @Test func a404MUnknownOutsideProfileLookupIsNotRemapped() async {
        let driver = FakeProfileDriver()
        driver.error = ClientError.MatrixApi(
            kind: .unknown, code: "M_UNKNOWN", msg: "No row found (profiles)",
            details: "Error { status_code: 404, kind: Unknown }")
        let service = makeService(driver)
        await #expect {
            try await service.removeAvatar()
        } throws: { error in
            if case MatrixError.unexpected = error { true } else { false }
        }
    }

    @Test func setDisplayNamePassesNameAsIs() async throws {
        let driver = FakeProfileDriver()
        let service = makeService(driver)
        try await service.setDisplayName("Alice B.")
        try await service.setDisplayName("")
        #expect(driver.names == ["Alice B.", ""])
    }

    @Test func setAvatarPassesBytesAndMimeType() async throws {
        let driver = FakeProfileDriver()
        try await makeService(driver).setAvatar(Data([9, 8]), mimeType: "image/png")
        #expect(driver.avatars == [AvatarCall(mimeType: "image/png", data: Data([9, 8]))])
    }

    @Test func removeAvatarReachesUpstream() async throws {
        let driver = FakeProfileDriver()
        try await makeService(driver).removeAvatar()
        #expect(driver.removals == 1)
    }

    @Test func setPresenceIsImmediate() async throws {
        let driver = FakeProfileDriver()
        try await makeService(driver).setPresence(.unavailable)
        #expect(driver.presences == [PresenceCall(presence: .unavailable, immediate: true)])
    }

    @Test func forbiddenNameIsPermissionError() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.forbidden)
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.setDisplayName("x") }
        await #expect(throws: MatrixError.permission(.forbidden)) {
            try await service.setAvatar(Data(), mimeType: "image/png")
        }
    }

    @Test func tooLargeAvatarIsExplicitUnexpected() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.tooLarge)
        let service = makeService(driver)
        await #expect(
            throws: MatrixError.unexpected(message: "The media is larger than the homeserver accepts.", details: "M_X")
        ) { try await service.setAvatar(Data([1]), mimeType: "image/png") }
    }

    @Test func notFoundOutsideProfileLookupIsNotRemapped() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.notFound)
        let service = makeService(driver)
        await #expect(throws: MatrixError.notFound(.unspecified)) { try await service.removeAvatar() }
    }

    @Test func setPresenceErrorIsMapped() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.forbidden)
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.setPresence(.online) }
    }

    @Test func profileErrorOtherThanNotFoundIsNotRemapped() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.forbidden)
        let service = makeService(driver)
        await #expect(throws: MatrixError.permission(.forbidden)) { try await service.profile(of: alice) }
    }

    @Test func tooLargeAvatarKeepsUpstreamDetails() async {
        let driver = FakeProfileDriver()
        driver.error = apiError(.tooLarge, details: "limit 1MB")
        let service = makeService(driver)
        await #expect(
            throws: MatrixError.unexpected(
                message: "The media is larger than the homeserver accepts.", details: "M_X: limit 1MB")
        ) { try await service.setAvatar(Data([1]), mimeType: "image/png") }
    }

    @Test(arguments: [
        ("MXC://example.org/a", true),
        ("mxc://example.org/a", true),
        ("mxc://", false),
        ("https://example.org/a", false),
    ])
    func avatarFollowsTheSameRuleAsSenderAvatar(url: String, isAvatar: Bool) async throws {
        let driver = FakeProfileDriver()
        driver.profile = MatrixRustSDK.UserProfile(
            userId: "@alice:example.org", displayName: nil, avatarUrl: url, status: nil, call: nil)
        let profile = try await makeService(driver).profile(of: alice)
        #expect((profile.avatar != nil) == isAvatar)
        #expect(profile.avatar == MatrixClientKitCore.MediaSource(url: url))
    }

    @Test(arguments: [
        (Presence.online, PresenceState.online),
        (.unavailable, .unavailable),
        (.offline, .offline),
    ])
    func presenceMapsToUpstream(presence: Presence, upstream: PresenceState) {
        #expect(ProfileMapper.upstreamPresence(from: presence) == upstream)
    }

    @Test(arguments: [
        (PresenceState.online, Presence.online),
        (.unavailable, .unavailable),
        (.offline, .offline),
    ])
    func presenceMapsFromUpstream(upstream: PresenceState, presence: Presence) {
        #expect(ProfileMapper.presence(from: upstream) == presence)
    }
}
