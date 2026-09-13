import Testing
import Foundation
import MatrixClientKit

@Test func factoryBuildsAClientForTheGivenHomeserver() {
    let homeserver = URL(string: "https://matrix.org")!
    let client = Matrix.client(
        homeserver: homeserver,
        storage: .local(directory: URL(fileURLWithPath: NSTemporaryDirectory()))
    )

    #expect(client.homeserver == homeserver)
}

@Test func coreTypesAreReExportedByTheUmbrella() {
    // Compile uniquement si `@_exported import MatrixClientKitCore` est en place.
    #expect(UserID(rawValue: "@alice:matrix.org") != nil)
    #expect(PackageInfo.upstreamVersion == "26.09.07")
}
