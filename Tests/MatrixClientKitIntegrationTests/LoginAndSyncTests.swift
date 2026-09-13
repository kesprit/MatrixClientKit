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

private func makeClient(_ configuration: IntegrationConfiguration) -> any MatrixClient {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
    return Matrix.client(homeserver: configuration.homeserver, storage: .local(directory: directory))
}

@Suite(.enabled(if: IntegrationConfiguration.isAvailable))
struct LoginAndSyncTests {

    // Les tests ci-dessous attendent un élément d'un `AsyncStream` (un état de sync, un écho
    // local) qui peut ne jamais arriver si le chemin testé est cassé. Sans borne, un `for await`
    // sur un flux qui ne produit plus rien fait pendre la suite indéfiniment au lieu de la faire
    // échouer — inacceptable pour une suite lancée à la main contre un vrai homeserver, où la
    // personne qui la lance se retrouve à attendre sans le moindre indice. `.timeLimit` est le
    // mécanisme idiomatique de Swift Testing pour borner un test dans son ensemble.
    @Test(.timeLimit(.minutes(1)))
    func loginSyncAndListRooms() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let client = makeClient(configuration)

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

        for await rooms in session.rooms.list(filter: .joined) {
            #expect(rooms.allSatisfy { $0.membership == .joined })
            break
        }

        await session.sync.stop()
        try await session.logout()
    }

    @Test func wrongPasswordSurfacesAsInvalidCredentials() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let client = makeClient(configuration)

        await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
            _ = try await client.login(
                .password(
                    username: configuration.username,
                    password: "mot-de-passe-volontairement-faux",
                    deviceName: nil
                )
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sendingAMessageProducesALocalEcho() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let environment = ProcessInfo.processInfo.environment
        let roomIdentifier = try #require(environment["MATRIX_TEST_ROOM_ID"])
        let roomID = try #require(RoomID(rawValue: roomIdentifier))

        let client = makeClient(configuration)
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

        await session.sync.stop()
        try await session.logout()
    }
}
