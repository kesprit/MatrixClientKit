import Testing
import Foundation
import MatrixClientKit
@testable import MatrixClientKitRust

/// Push et extension (spec 0.3, §11). Les cas qui ouvrent une session se déconnectent en fin de
/// cas ; voir le README de la suite pour les contraintes sur les comptes.
@Suite(.enabled(if: IntegrationConfiguration.isAvailable), .serialized)
struct NotificationTests {

    /// Cas 1 et 2 : l'extension résout le message d'un autre compte pendant que la session
    /// d'application est ouverte sur le même stockage, et la session d'application reste
    /// utilisable ensuite.
    @Test(.enabled(if: IntegrationConfiguration.hasSenderAccount), .timeLimit(.minutes(3)))
    func theExtensionResolvesAMessageWhileTheApplicationIsOpen() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let roomID = try #require(configuration.roomID)
        let senderDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mck-integration-\(UUID().uuidString)", isDirectory: true)
        let storage = appGroupStorage()

        // L'expéditeur d'abord : sa connexion écrit l'entrée Keychain partagée, que la connexion
        // du compte principal écrase ensuite (voir le README).
        let sender = try await signIn(
            configuration,
            storage: .local(directory: senderDirectory),
            username: configuration.senderUsername,
            password: configuration.senderPassword,
            deviceName: "MatrixClientKit Integration (sender)"
        )
        let application = try await signIn(
            configuration,
            storage: storage,
            deviceName: "MatrixClientKit Integration (app)"
        )

        // Laisse à la sync de l'expéditeur le temps d'apprendre le nouvel appareil du compte
        // principal : sans cela, la clé du message ne lui est pas partagée et il reste
        // indéchiffrable — ce que le cas détecterait comme un échec.
        try await Task.sleep(for: .seconds(3))

        let body = "notification d'intégration \(UUID().uuidString)"
        let eventID = try await sendText(body, in: roomID, from: sender)

        let service = try await MatrixNotificationService(storage: storage)
        let result = try await service.notification(roomID: roomID, eventID: eventID)

        guard case let .notification(notification) = result else {
            Issue.record("résultat inattendu : \(result)")
            await cleaningUp {
                try? await application.logout()
                try? await sender.logout()
                removeAppGroup(storage)
                removeDirectory(senderDirectory)
            }
            return
        }
        #expect(notification.kind == .message(body: body))
        #expect(notification.sender.rawValue.hasPrefix("@\(configuration.senderUsername ?? "")"))
        #expect(notification.roomID == roomID)

        // Cas 2 : la session d'application n'a été ni déconnectée ni bloquée par l'extension.
        let reply = "réponse d'intégration \(UUID().uuidString)"
        _ = try await sendText(reply, in: roomID, from: application)

        await cleaningUp {
            try? await application.logout()
            try? await sender.logout()
            removeAppGroup(storage)
            removeDirectory(senderDirectory)
        }
    }

    /// Cas 3 : le homeserver accepte l'enregistrement et la suppression du pusher.
    @Test(.timeLimit(.minutes(1)))
    func aPusherIsRegisteredThenRemoved() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let storage = appGroupStorage()
        let session = try await signIn(
            configuration,
            storage: storage,
            deviceName: "MatrixClientKit Integration (pusher)"
        )
        let token = try await rawAccessToken(configuration)
        let pusher = PusherConfiguration(
            deviceToken: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
            appID: "com.matrixclientkit.integration",
            gatewayURL: URL(string: "https://push.matrixclientkit.invalid/_matrix/push/v1/notify")!,
            appDisplayName: "MatrixClientKit Integration",
            deviceDisplayName: "Integration",
            language: "en"
        )

        try await session.notifications.registerPusher(pusher)
        #expect(try await pushers(configuration, accessToken: token).contains(pusher.pushKey))

        try await session.notifications.unregisterPusher(pusher)
        #expect(try await !pushers(configuration, accessToken: token).contains(pusher.pushKey))

        await cleaningUp {
            try? await rawLogout(configuration, accessToken: token)
            try? await session.logout()
            removeAppGroup(storage)
        }
    }

    /// Cas 4 : le mode d'un salon se change puis se restaure.
    @Test(.enabled(if: IntegrationConfiguration.hasRoom), .timeLimit(.minutes(1)))
    func aRoomModeIsChangedThenRestored() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let roomID = try #require(configuration.roomID)
        let storage = appGroupStorage()
        let session = try await signIn(
            configuration,
            storage: storage,
            deviceName: "MatrixClientKit Integration (settings)"
        )
        for await snapshot in session.rooms.list(filter: .joined) where snapshot.contains(where: { $0.id == roomID }) {
            break
        }

        try await session.notifications.setNotificationMode(.mute, for: roomID)
        let muted = try await session.notifications.notificationSettings(for: roomID)
        try await session.notifications.restoreDefaultNotificationMode(for: roomID)
        let restored = try await session.notifications.notificationSettings(for: roomID)

        #expect(muted == RoomNotificationSettings(mode: .mute, isDefault: false))
        #expect(restored.isDefault)

        await cleaningUp {
            try? await session.logout()
            removeAppGroup(storage)
        }
    }

    /// Cas 5 : un store créé par un client sans verrou, comme en 0.2, se restaure avec le verrou.
    @Test(.timeLimit(.minutes(2)))
    func aStoreCreatedWithoutTheLockIsRestoredWithIt() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let storage = appGroupStorage()
        let legacy = RustMatrixClient(
            homeserver: configuration.homeserver,
            restorer: SessionRestorer(storage: storage, lockPolicy: .unset)
        )
        let first = try await legacy.login(
            .password(
                username: configuration.username,
                password: configuration.password,
                deviceName: "MatrixClientKit Integration (0.2 store)"
            )
        )
        let firstStates = first.sync.state
        await first.sync.start()
        _ = await firstValue(of: firstStates) { $0 == .running }
        await first.sync.stop()

        let restored = try #require(try await Matrix.restoreSession(storage: storage))
        let states = restored.sync.state
        await restored.sync.start()
        let running = await firstValue(of: states) { $0 == .running }

        #expect(running == .running)
        #expect(restored.userID == first.userID)

        await cleaningUp {
            try? await restored.logout()
            removeAppGroup(storage)
        }
    }
}
