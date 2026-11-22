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

    @Test(arguments: [
        "http://account.example.org/", "http://localhost.example.org/", "http://example.org:8082/",
        "http://notlocalhost/", "http://128.0.0.1/", "http://[::2]/", "http://127.0.0.1.example.org/",
        "ftp://account.example.org/", "myapp://account", "file:///etc/passwd", "javascript:alert(1)",
        "ftp://localhost/", "myapp://localhost/",
    ])
    func aNonHTTPSNonLoopbackURLIsUnexpected(_ string: String) {
        #expect { try AccountMapper.managementURL(from: string) } throws: { error in
            if case MatrixError.unexpected = error { true } else { false }
        }
    }

    /// Le serveur d'autorisation d'un développement local (le harnais d'intégration) sert en `http`.
    @Test(arguments: [
        "http://localhost:8082/account/", "http://LOCALHOST/", "http://mas.localhost:8080/",
        "http://127.0.0.1/account", "http://127.255.0.3:8080/", "http://[::1]:8080/account",
        "HTTPS://account.example.org/",
    ])
    func httpOnLoopbackAndHTTPSAreAccepted(_ string: String) throws {
        #expect(try AccountMapper.managementURL(from: string) == URL(string: string))
    }

    @Test func malformedURLIsUnexpected() {
        for malformed in ["not a url with spaces", ""] {
            #expect { try AccountMapper.managementURL(from: malformed) } throws: { error in
                if case MatrixError.unexpected = error { true } else { false }
            }
        }
    }

    @Test func ignoredUsersDropsMalformedIdentifiers() {
        let users = AccountMapper.userIDs(from: ["@a:x.org", "garbage", "@b:x.org"])
        #expect(users.map(\.rawValue) == ["@a:x.org", "@b:x.org"])
    }
}
