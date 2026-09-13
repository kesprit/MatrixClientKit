import Testing
import Foundation
import MatrixClientKit

/// Configuration lue dans l'environnement. Absente, la suite entière est ignorée.
private struct IntegrationConfiguration {
    let homeserver: URL
    let username: String
    let password: String

    static var current: IntegrationConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let homeserver = environment["MATRIX_TEST_HOMESERVER"].flatMap(URL.init(string:)),
            let username = environment["MATRIX_TEST_USERNAME"],
            let password = environment["MATRIX_TEST_PASSWORD"]
        else { return nil }

        return IntegrationConfiguration(homeserver: homeserver, username: username, password: password)
    }

    static var isAvailable: Bool { current != nil }
}

/// Client d'intégration et répertoire qui l'héberge.
///
/// Le répertoire est rendu à l'appelant : sans cela, chaque exécution laisse sous le répertoire
/// temporaire un store SQLite contenant une vraie session — jetons compris.
private struct IntegrationClient {
    let client: any MatrixClient
    let directory: URL
}

private func makeClient(_ configuration: IntegrationConfiguration) -> IntegrationClient {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
    return IntegrationClient(
        client: Matrix.client(homeserver: configuration.homeserver, storage: .local(directory: directory)),
        directory: directory
    )
}

/// Exécute un nettoyage même lorsque la tâche de test a été annulée — par exemple par
/// `.timeLimit` lorsqu'un flux attendu ne produit jamais la valeur cherchée. Une tâche détachée
/// n'hérite pas de l'annulation de son appelant, donc `session.logout()` a une vraie chance
/// d'atteindre le serveur au lieu d'échouer immédiatement sur un contexte déjà annulé.
private func cleaningUp(_ body: @escaping @Sendable () async -> Void) async {
    await Task.detached(operation: body).value
}

/// Supprime le répertoire de travail d'une exécution. L'échec est ignoré : le nettoyage ne doit
/// jamais masquer le résultat du test qu'il suit.
private func removeDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

@Suite(.enabled(if: IntegrationConfiguration.isAvailable))
struct LoginAndSyncTests {

    // Les tests ci-dessous attendent un élément d'un `AsyncStream` (un état de sync, une liste de
    // rooms, un écho local) qui peut ne jamais arriver si le chemin testé est cassé. Sans borne,
    // un `for await` sur un flux qui ne produit plus rien fait pendre la suite indéfiniment au
    // lieu de la faire échouer — inacceptable pour une suite lancée à la main contre un vrai
    // homeserver, où la personne qui la lance se retrouve à attendre sans le moindre indice.
    // `.timeLimit` est le mécanisme idiomatique de Swift Testing pour borner un test dans son
    // ensemble ; on le pose aussi sur le test de mot de passe erroné, qui fait un vrai appel
    // réseau et peut pendre tout autant qu'une boucle sur un flux.
    @Test(.timeLimit(.minutes(1)))
    func loginSyncAndListRooms() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let integration = makeClient(configuration)
        let client = integration.client
        let directory = integration.directory

        let session = try await client.login(
            .password(
                username: configuration.username,
                password: configuration.password,
                deviceName: "MatrixClientKit Integration"
            )
        )

        await session.sync.start()

        var states: [SyncState] = []
        for await state in session.sync.state {
            states.append(state)
            if state == .running { break }
        }
        #expect(states.contains(.running))

        var receivedRooms: [RoomSummary]?
        for await rooms in session.rooms.list(filter: .joined) {
            receivedRooms = rooms
            break
        }

        // Un instantané vide ferait passer `allSatisfy` sans avoir vérifié quoi que ce soit ; le
        // compte de test doit donc appartenir à au moins une room jointe (voir README).
        let rooms = try #require(receivedRooms, "aucun instantané de liste de rooms n'a été reçu")
        #expect(!rooms.isEmpty, "le compte de test doit appartenir à au moins une room rejointe")
        #expect(rooms.allSatisfy { $0.membership == .joined })

        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
            removeDirectory(directory)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func wrongPasswordSurfacesAsInvalidCredentials() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let integration = makeClient(configuration)
        let client = integration.client
        let directory = integration.directory

        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            _ = try await client.login(
                .password(
                    username: configuration.username,
                    password: "mot-de-passe-volontairement-faux",
                    deviceName: nil
                )
            )
        }

        await cleaningUp { removeDirectory(directory) }
    }

    @Test(.timeLimit(.minutes(1)))
    func sendingAMessageProducesALocalEcho() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let environment = ProcessInfo.processInfo.environment
        let roomIdentifier = try #require(environment["MATRIX_TEST_ROOM_ID"])
        let roomID = try #require(RoomID(rawValue: roomIdentifier))

        let integration = makeClient(configuration)
        let client = integration.client
        let directory = integration.directory
        let session = try await client.login(
            .password(
                username: configuration.username,
                password: configuration.password,
                deviceName: "MatrixClientKit Integration"
            )
        )
        await session.sync.start()

        let room = try await session.rooms.room(roomID)
        let timeline = try await room.timeline()
        let body = "test d'intégration \(UUID().uuidString)"

        let stream = timeline.items
        try await timeline.send(.text(body))

        var found = false
        for await items in stream {
            if items.contains(where: { $0.message?.body == body }) {
                found = true
                break
            }
        }
        #expect(found)

        await cleaningUp {
            await session.sync.stop()
            try? await session.logout()
            removeDirectory(directory)
        }
    }
}
