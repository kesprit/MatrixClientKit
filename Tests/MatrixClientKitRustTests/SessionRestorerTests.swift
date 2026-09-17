import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let persistedHomeserver = URL(string: "https://matrix-client.persisted.example")!

private func makeRestorer() -> SessionRestorer {
    SessionRestorer(
        storage: .local(directory: FileManager.default.temporaryDirectory),
        secureStore: InMemorySecureStore()
    )
}

private func persistedSession() -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:persisted.example")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: persistedHomeserver,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func restoringBuildsTheClientForThePersistedHomeserver() async throws {
    let restorer = makeRestorer()
    try restorer.persistence.save(persistedSession())
    var requestedHomeserver: URL?

    do {
        _ = try await restorer.restore { homeserver, _ in
            requestedHomeserver = homeserver
            throw MatrixError.storage(.unavailable)
        }
        Issue.record("la fabrique de client a échoué : la restauration doit relayer l'erreur")
    } catch {
        #expect(error as? MatrixError == .storage(.unavailable))
    }

    // La session appartient au serveur qui l'a émise : aucune autre adresse ne doit être utilisée.
    #expect(requestedHomeserver == persistedHomeserver)
    // Un échec de stockage ne dit rien de la validité de la session : elle est conservée.
    #expect(try restorer.persistence.load() != nil)
}

@Test func restoringWithoutAPersistedSessionBuildsNoClient() async throws {
    let restorer = makeRestorer()
    var clientWasBuilt = false

    let session = try await restorer.restore { _, _ in
        clientWasBuilt = true
        throw MatrixError.storage(.unavailable)
    }

    #expect(session == nil)
    #expect(!clientWasBuilt)
}
