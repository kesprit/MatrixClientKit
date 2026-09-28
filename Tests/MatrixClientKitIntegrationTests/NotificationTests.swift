import Testing
import Foundation
import MatrixClientKit
@testable import MatrixClientKitRust

extension IntegrationTests {
    /// Push et extension (spec 0.3, §11). Les cas qui ouvrent une session se déconnectent en fin
    /// de cas, sur tout chemin de sortie (succès, résultat inattendu ou erreur) ; voir le README
    /// de la suite pour les contraintes sur les comptes. Sérialisée avec le reste de
    /// ``IntegrationTests`` : cette suite partage elle aussi le compte de test et l'entrée
    /// Keychain du processus avec les autres suites d'intégration.
    @Suite
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

                let resolver = try await MatrixNotificationResolver(storage: storage)
                let result = try await resolver.notification(roomID: roomID, eventID: eventID)

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

            var firstUserID: UserID?
            var restored: (any MatrixSession)?

            // Contrairement aux autres cas, il n'y a pas de `first` capturé ici : le client 0.2 et
            // sa session sont scopés à ``loginWithLegacyClient()`` ci-dessous et n'ont donc plus de
            // référent une fois celle-ci retournée (voir son commentaire). Le nettoyage n'a donc que
            // `restored` pour déconnecter l'appareil ; s'il n'existe pas encore (restauration jamais
            // tentée ou en échec), on rouvre le store une dernière fois par une restauration fraîche,
            // seulement pour ça — les identifiants du client 0.2 sont toujours sur disque, ce client
            // lui-même n'est plus nécessaire pour les lire.
            func cleanup() async {
                let openedRestored = restored
                await cleaningUp {
                    if let openedRestored {
                        try? await openedRestored.logout()
                    } else if let freshSession = try? await Matrix.restoreSession(storage: storage) {
                        try? await freshSession.logout()
                    }
                    removeAppGroup(storage)
                }
            }

            do {
                // Isolée dans une fonction locale pour que `legacy` et sa session se libèrent dès la
                // fin de cette étape, avant la restauration, plutôt qu'à la fin du `do` : aucune des
                // deux n'est capturée par une variable qui survivrait à son retour, seul `firstUserID`
                // en sort, pour la comparaison finale.
                func loginWithLegacyClient() async throws -> UserID {
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
                    let firstStates = localFirst.sync.state
                    await localFirst.sync.start()
                    let firstState = await waitUntilRunning(firstStates)
                    try #require(firstState == .running, "initial sync reached \(String(describing: firstState))")
                    await localFirst.sync.stop()
                    return localFirst.userID
                }
                // Le client 0.2 (`legacy`) et sa session ne survivent pas à cet appel : sans ça, deux
                // clients resteraient ouverts sur le même store SQLite pendant la restauration —
                // l'un sans verrou, l'autre avec — ce qu'un vrai relaunch de l'application ne
                // reproduirait jamais, puisqu'il ferme entièrement le premier client avant d'ouvrir
                // le second.
                firstUserID = try await loginWithLegacyClient()

                let localRestored = try #require(try await Matrix.restoreSession(storage: storage))
                restored = localRestored
                let states = localRestored.sync.state
                await localRestored.sync.start()
                let state = await waitUntilRunning(states)

                #expect(state == .running, "sync reached \(String(describing: state))")
                #expect(localRestored.userID == firstUserID)
            } catch {
                await cleanup()
                throw error
            }

            await cleanup()
        }
    }
}
