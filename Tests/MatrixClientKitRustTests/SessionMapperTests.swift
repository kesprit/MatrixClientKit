import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private func makeUpstreamSession() -> Session {
    Session(
        accessToken: "token",
        refreshToken: "refresh",
        userId: "@alice:matrix.org",
        deviceId: "DEV1",
        homeserverUrl: "https://matrix.org",
        oauthData: nil,
        slidingSyncVersion: .native
    )
}

@Test func upstreamSessionConvertsToSessionData() throws {
    let data = try SessionMapper.sessionData(from: makeUpstreamSession())

    #expect(data.userID.rawValue == "@alice:matrix.org")
    #expect(data.deviceID.rawValue == "DEV1")
    #expect(data.homeserverURL == URL(string: "https://matrix.org"))
    #expect(data.accessToken == "token")
    #expect(data.refreshToken == "refresh")
    #expect(data.slidingSyncVersion == "native")
}

@Test func sessionDataConvertsBackToUpstreamSession() throws {
    let data = try SessionMapper.sessionData(from: makeUpstreamSession())
    let session = SessionMapper.session(from: data)

    #expect(session.accessToken == "token")
    #expect(session.userId == "@alice:matrix.org")
    #expect(session.deviceId == "DEV1")
    #expect(session.homeserverUrl == "https://matrix.org")
}

@Test func malformedUserIdentifierSurfacesAsUnexpectedError() {
    let session = Session(
        accessToken: "token",
        refreshToken: nil,
        userId: "alice-sans-arobase",
        deviceId: "DEV1",
        homeserverUrl: "https://matrix.org",
        oauthData: nil,
        slidingSyncVersion: .native
    )

    #expect(throws: MatrixError.self) {
        _ = try SessionMapper.sessionData(from: session)
    }
}
