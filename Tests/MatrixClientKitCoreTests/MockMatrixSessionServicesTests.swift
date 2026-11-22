import MatrixClientKitCore
import MatrixClientKitMocks
import Testing

@Suite struct MockMatrixSessionServicesTests {
    @Test func profileAndAccountDefaultToFreshMocks() {
        let session = MockMatrixSession()
        #expect(session.profile is MockProfileService)
        #expect(session.account is MockAccountService)
    }

    @Test func profileAndAccountAreInjectable() {
        let profile = MockProfileService()
        let account = MockAccountService()
        let session = MockMatrixSession(profile: profile, account: account)
        #expect((session.profile as? MockProfileService) === profile)
        #expect((session.account as? MockAccountService) === account)
    }

    @Test func sessionExposesTheServicesThroughTheProtocol() async throws {
        let session: any MatrixSession = MockMatrixSession()
        try await session.profile.setDisplayName("Alice")
        #expect(try await session.account.managementURL(for: .overview) == nil)
    }
}
