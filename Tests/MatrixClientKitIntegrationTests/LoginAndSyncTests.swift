import Testing
import Foundation
import MatrixClientKit

extension IntegrationTests {
    // Sérialisée avec le reste de ``IntegrationTests`` : les trois cas se connectent au même
    // compte et partagent donc le même store et les mêmes entrées Keychain que les autres suites
    // d'intégration. Voir le commentaire sur ``IntegrationTests`` pour la raison de la
    // sérialisation inter-suites.
    @Suite
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

            let states = session.sync.state
            await session.sync.start()
            let state = await waitUntilRunning(states)
            #expect(state == .running, "sync reached \(String(describing: state))")

            // La liste part vide et se remplit à la première réponse de sync : prendre le premier
            // instantané venu testerait l'état initial, pas la synchronisation. On attend donc le
            // premier instantané non vide — la borne de temps du test fait échouer l'attente si la
            // sync ne produit jamais rien.
            var rooms: [RoomSummary] = []
            for await snapshot in session.rooms.list(filter: .joined) {
                guard !snapshot.isEmpty else { continue }
                rooms = snapshot
                break
            }

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

            // `room(_:)` interroge la liste synchronisée : tant que la sync n'a pas fait apparaître
            // la room, elle répond qu'elle n'existe pas. On attend sa visibilité avant de la demander.
            for await snapshot in session.rooms.list(filter: .joined) {
                if snapshot.contains(where: { $0.id == roomID }) { break }
            }

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
}
