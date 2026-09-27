import Testing
import Foundation
import MatrixClientKit
@testable import MatrixClientKitRust

/// Push et extension (spec 0.3, §11). Les cas qui ouvrent une session se déconnectent en fin de
/// cas, sur tout chemin de sortie (succès, résultat inattendu ou erreur) ; voir le README de la
/// suite pour les contraintes sur les comptes.
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

        var sender: (any MatrixSession)?
        var application: (any MatrixSession)?

        // Nettoyage centralisé, appelé sur chaque chemin de sortie : l'expéditeur se déconnecte
        // toujours en dernier (voir le README), et une ressource pas encore acquise au moment de
        // l'appel est simplement ignorée.
        func cleanup() async {
            let signedInSender = sender
            let signedInApplication = application
            await cleaningUp {
                try? await signedInApplication?.logout()
                try? await signedInSender?.logout()
                removeAppGroup(storage)
                removeDirectory(senderDirectory)
            }
        }

        do {
            // L'expéditeur d'abord : sa connexion écrit l'entrée Keychain partagée, que la
            // connexion du compte principal écrase ensuite (voir le README).
            let localSender = try await signIn(
                configuration,
                storage: .local(directory: senderDirectory),
                username: configuration.senderUsername,
                password: configuration.senderPassword,
                deviceName: "MatrixClientKit Integration (sender)"
            )
            sender = localSender
            let localApplication = try await signIn(
                configuration,
                storage: storage,
                deviceName: "MatrixClientKit Integration (app)"
            )
            application = localApplication

            // Laisse à la sync de l'expéditeur le temps d'apprendre le nouvel appareil du compte
            // principal : sans cela, la clé du message ne lui est pas partagée et il reste
            // indéchiffrable — ce que le cas détecterait comme un échec.
            try await Task.sleep(for: .seconds(3))

            let body = "notification d'intégration \(UUID().uuidString)"
            let eventID = try await sendText(body, in: roomID, from: localSender)

            let service = try await MatrixNotificationService(storage: storage)
            let result = try await service.notification(roomID: roomID, eventID: eventID)

            guard case let .notification(notification) = result else {
                Issue.record("résultat inattendu : \(result)")
                await cleanup()
                return
            }
            #expect(notification.kind == .message(body: body))
            #expect(notification.sender == localSender.userID)
            #expect(notification.roomID == roomID)

            // Cas 2 : la session d'application n'a été ni déconnectée ni bloquée par l'extension.
            let reply = "réponse d'intégration \(UUID().uuidString)"
            _ = try await sendText(reply, in: roomID, from: localApplication)
        } catch {
            await cleanup()
            throw error
        }

        await cleanup()
    }

    /// Cas 3 : le homeserver accepte l'enregistrement et la suppression du pusher.
    @Test(.timeLimit(.minutes(1)))
    func aPusherIsRegisteredThenRemoved() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let storage = appGroupStorage()

        var session: (any MatrixSession)?
        var token: String?

        // Nettoyage centralisé : l'appareil brut ouvert par `rawAccessToken` est aussi déconnecté
        // s'il a été obtenu, même si une étape suivante échoue.
        func cleanup() async {
            let openedSession = session
            let openedToken = token
            await cleaningUp {
                if let openedToken {
                    try? await rawLogout(configuration, accessToken: openedToken)
                }
                try? await openedSession?.logout()
                removeAppGroup(storage)
            }
        }

        do {
            let localSession = try await signIn(
                configuration,
                storage: storage,
                deviceName: "MatrixClientKit Integration (pusher)"
            )
            session = localSession
            let localToken = try await rawAccessToken(configuration)
            token = localToken

            let pusher = PusherConfiguration(
                deviceToken: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
                appID: "com.matrixclientkit.integration",
                gatewayURL: URL(string: "https://push.matrixclientkit.invalid/_matrix/push/v1/notify")!,
                appDisplayName: "MatrixClientKit Integration",
                deviceDisplayName: "Integration",
                language: "en"
            )

            try await localSession.notifications.registerPusher(pusher)
            #expect(try await pushers(configuration, accessToken: localToken).contains(pusher.pushKey))

            try await localSession.notifications.unregisterPusher(pusher)
            #expect(try await !pushers(configuration, accessToken: localToken).contains(pusher.pushKey))
        } catch {
            await cleanup()
            throw error
        }

        await cleanup()
    }

    /// Cas 4 : le mode d'un salon se change puis se restaure.
    @Test(.enabled(if: IntegrationConfiguration.hasRoom), .timeLimit(.minutes(1)))
    func aRoomModeIsChangedThenRestored() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let roomID = try #require(configuration.roomID)
        let storage = appGroupStorage()

        var session: (any MatrixSession)?
        func cleanup() async {
            let openedSession = session
            await cleaningUp {
                try? await openedSession?.logout()
                removeAppGroup(storage)
            }
        }

        do {
            let localSession = try await signIn(
                configuration,
                storage: storage,
                deviceName: "MatrixClientKit Integration (settings)"
            )
            session = localSession
            for await snapshot in localSession.rooms.list(filter: .joined)
            where snapshot.contains(where: { $0.id == roomID }) {
                break
            }

            try await localSession.notifications.setNotificationMode(.mute, for: roomID)
            let muted = try await localSession.notifications.notificationSettings(for: roomID)
            try await localSession.notifications.restoreDefaultNotificationMode(for: roomID)
            let restored = try await localSession.notifications.notificationSettings(for: roomID)

            #expect(muted == RoomNotificationSettings(mode: .mute, isDefault: false))
            #expect(restored.isDefault)
        } catch {
            await cleanup()
            throw error
        }

        await cleanup()
    }

    /// Cas 5 : un store créé par un client sans verrou, comme en 0.2, se restaure avec le verrou.
    @Test(.timeLimit(.minutes(2)))
    func aStoreCreatedWithoutTheLockIsRestoredWithIt() async throws {
        let configuration = try #require(IntegrationConfiguration.current)
        let storage = appGroupStorage()

        var first: (any MatrixSession)?
        var restored: (any MatrixSession)?

        // `first` et `restored` désignent le même appareil serveur ; déconnecter `restored` s'il
        // existe suffit. Sinon, si seul `first` a pu s'ouvrir, c'est lui qu'il faut déconnecter.
        func cleanup() async {
            let openedFirst = first
            let openedRestored = restored
            await cleaningUp {
                if let openedRestored {
                    try? await openedRestored.logout()
                } else {
                    try? await openedFirst?.logout()
                }
                removeAppGroup(storage)
            }
        }

        do {
            let legacy = RustMatrixClient(
                homeserver: configuration.homeserver,
                restorer: SessionRestorer(storage: storage, lockPolicy: .unset)
            )
            let localFirst = try await legacy.login(
                .password(
                    username: configuration.username,
                    password: configuration.password,
                    deviceName: "MatrixClientKit Integration (0.2 store)"
                )
            )
            first = localFirst
            let firstStates = localFirst.sync.state
            await localFirst.sync.start()
            _ = await firstValue(of: firstStates) { $0 == .running }
            await localFirst.sync.stop()

            let localRestored = try #require(try await Matrix.restoreSession(storage: storage))
            restored = localRestored
            let states = localRestored.sync.state
            await localRestored.sync.start()
            let running = await firstValue(of: states) { $0 == .running }

            #expect(running == .running)
            #expect(localRestored.userID == localFirst.userID)
        } catch {
            await cleanup()
            throw error
        }

        await cleanup()
    }
}
