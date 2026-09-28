import Testing
import Foundation
import MatrixClientKit
import MatrixClientKitCore
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
        ///
        /// Modélise une vraie mise à jour 0.2 → 0.3, qui est un relancement : le store 0.2 est créé
        /// par l'exécutable `IntegrationLegacySeeder`, dans un processus qui se termine avant que le
        /// client 0.3 de ce processus-ci ne l'ouvre. Deux clients sur un même store dans un même
        /// processus — ce que faisait ce cas auparavant — n'arrive jamais dans une application, et
        /// ce montage bloquait par intermittence dans un appel du SDK insensible à l'annulation.
        ///
        /// Les secrets du client 0.2 (session et clé du store) reviennent par le tube du seeder et
        /// sont écrits ici dans le Keychain, sous l'identité de ce processus : sur macOS, une entrée
        /// écrite par un autre exécutable ne se lit pas sans dialogue d'autorisation, alors qu'une
        /// application relancée retrouve les siennes. Le format des entrées est celui du client,
        /// inchangé entre 0.2 et 0.3 ; ce qui est vérifié, c'est le store créé sans verrou.
        @Test(.timeLimit(.minutes(3)))
        func aStoreCreatedWithoutTheLockIsRestoredWithIt() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let appGroup = newAppGroupIdentifier()
            let storage = appGroupStorage(appGroup)

            var legacyAccessToken: String?
            var writtenSecretKeys: [String] = []
            var restored: (any MatrixSession)?

            // Le nettoyage déconnecte l'appareil par la session restaurée si elle existe ; sinon
            // (restauration jamais tentée ou en échec) par `rawLogout` avec le jeton rendu par le
            // seeder — la déconnexion HTTP brute du cas du pusher, indépendante de
            // `Matrix.restoreSession` elle-même : la retenter ici referait la manipulation que ce
            // cas vérifie, et échouerait probablement pour la même raison, laissant l'appareil
            // enregistré. Les entrées Keychain écrites par ce cas sont ensuite retirées dans tous
            // les cas : `logout()` les efface déjà, mais pas `rawLogout`.
            func cleanup() async {
                let openedRestored = restored
                let openedLegacyAccessToken = legacyAccessToken
                let openedSecretKeys = writtenSecretKeys
                await cleaningUp {
                    if let openedRestored {
                        try? await openedRestored.logout()
                    } else if let openedLegacyAccessToken {
                        try? await rawLogout(configuration, accessToken: openedLegacyAccessToken)
                    }
                    let keychain = KeychainSecureStore(storage: storage)
                    for key in openedSecretKeys {
                        try? keychain.removeValue(forKey: key)
                    }
                    removeAppGroup(storage)
                }
            }

            do {
                // Le seeder se connecte sans verrou, attend `.running`, arrête la sync et se
                // termine : à son retour, plus rien ne tient le store ouvert.
                let run = try await runLegacySeeder(appGroup: appGroup, timeout: .seconds(90))

                // Le jeton d'abord, même si le seeder a échoué après sa connexion : c'est ce qui
                // permet à ``cleanup()`` de déconnecter l'appareil qu'il a ouvert.
                let received = InMemorySecureStore()
                for (key, value) in run.seed?.secrets ?? [:] {
                    try received.set(value, forKey: key)
                }
                legacyAccessToken = try SessionPersistence(store: received).load()?.accessToken
                try #require(run.succeeded, "\(run.failureDescription)")
                let seed = try #require(run.seed)

                // Ce que retrouve l'application relancée : ses propres entrées Keychain.
                let keychain = KeychainSecureStore(storage: storage)
                writtenSecretKeys = Array(seed.secrets.keys)
                for (key, value) in seed.secrets {
                    try keychain.set(value, forKey: key)
                }

                let localRestored = try #require(try await Matrix.restoreSession(storage: storage))
                restored = localRestored
                let states = localRestored.sync.state
                await localRestored.sync.start()
                let state = await waitUntilRunning(states)

                #expect(state == .running, "sync reached \(String(describing: state))")
                #expect(localRestored.userID.rawValue == seed.userID)
            } catch {
                await cleanup()
                throw error
            }

            await cleanup()
        }
    }
}
