import Testing
import Foundation
@testable import MatrixClientKitCore

@Test func aSessionPersistedBy03DecodesWithoutStoreID() throws {
    // Forme exacte écrite par la 0.3 : aucun champ storeID.
    let json = """
        {"userID":"@alice:matrix.org","deviceID":"DEV1","homeserverURL":"https://matrix.org",
         "accessToken":"t","slidingSyncVersion":"native"}
        """
    let data = try JSONDecoder().decode(MatrixSessionData.self, from: Data(json.utf8))
    #expect(data.storeID == nil)
    #expect(data.userID.rawValue == "@alice:matrix.org")
}

@Test func theStoreIDSurvivesARoundTrip() throws {
    let original = MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!, deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!, accessToken: "t", refreshToken: nil,
        oauthData: nil, slidingSyncVersion: "native", storeID: "3f2a…"
    )
    let decoded = try JSONDecoder().decode(MatrixSessionData.self, from: JSONEncoder().encode(original))
    #expect(decoded.storeID == "3f2a…")
}
