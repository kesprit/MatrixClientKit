import Testing
import Foundation
import MatrixClientKit

extension HarnessTests {
    // Connexion, découverte et reconnexion contre le harnais Synapse local. Chaque cas supprime son
    // répertoire et déconnecte sa session, même interrompu (`cleaningUp`).
    @Suite
    struct AuthenticationHarnessTests {
        @Test(.timeLimit(.minutes(2)))
        func passwordLoginOpensAStoreNamedByItsStoreID() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(
                homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
            let session = try await client.login(
                .password(username: configuration.user, password: configuration.password, deviceName: "Harness")
            )
            let states = session.sync.state
            await session.sync.start()
            let state = await waitUntilRunning(states)

            // Un `storeID` est un UUID, avec tirets ; une empreinte 0.3 n'en a pas.
            let stores = storeDirectories(in: directory)
            #expect(state == .running, "sync reached \(String(describing: state))")
            #expect(stores.count == 1, "stores: \(stores)")
            #expect(stores.first?.contains("-") == true)

            await cleaningUp {
                await session.sync.stop()
                try? await session.logout()
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func emailLoginSucceeds() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(
                homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
            let session = try await client.login(
                .email(address: configuration.email, password: configuration.password, deviceName: "Harness (email)")
            )

            #expect(session.userID.rawValue == "@\(configuration.user):localhost")

            await cleaningUp { try? await session.logout() }
        }

        @Test(.timeLimit(.minutes(2)))
        func loginDetailsOnAPasswordServer() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(
                homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
            let details = try await client.loginDetails()

            #expect(details.supportsPassword)
            #expect(!details.supportsOAuth)
        }

        @Test(.timeLimit(.minutes(2)))
        func discoveryAcceptsAnURLString() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = try await Matrix.client(
                server: configuration.passwordHomeserver.absoluteString,
                storage: .local(directory: directory)
            )

            #expect(client.homeserver.absoluteString.hasPrefix(configuration.passwordHomeserver.absoluteString))
        }

        @Test(.timeLimit(.minutes(2)))
        func aFailedLoginLeavesNoStore() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(
                homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
            await #expect(throws: MatrixError.authentication(.invalidCredentials)) {
                _ = try await client.login(
                    .password(
                        username: configuration.user, password: "mot-de-passe-volontairement-faux", deviceName: nil)
                )
            }

            #expect(storeDirectories(in: directory).isEmpty, "stores: \(storeDirectories(in: directory))")
        }

        /// Le jeton de `synapse-expiring` vit 20 s : la session passe en soft logout pendant la
        /// sync, puis la reconnexion doit reprendre le même appareil, le même store et ses clés —
        /// prouvé par un message chiffré envoyé avant, relu en clair après.
        @Test(.timeLimit(.minutes(2)))
        func reauthenticationAfterSoftLogoutKeepsTheDeviceAndItsKeys() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }
            let roomID = try await createEncryptedRoom(
                on: configuration.expiringHomeserver, user: configuration.user, password: configuration.password
            )

            let client = Matrix.client(
                homeserver: configuration.expiringHomeserver, storage: .local(directory: directory))
            let old = try await client.login(
                .password(
                    username: configuration.user, password: configuration.password, deviceName: "Harness (soft logout)")
            )
            var current: any MatrixSession = old

            do {
                let states = old.sync.state
                await old.sync.start()
                let state = await waitUntilRunning(states)
                try #require(state == .running, "sync reached \(String(describing: state))")

                // Envoyé dans les 20 s de vie du jeton : la clé Megolm de ce message n'existe que
                // dans le store crypto de cet appareil.
                let body = "harness-soft-logout-\(UUID())"
                _ = try await sendText(body, in: roomID, from: old)

                // 20 s de vie du jeton, plus la requête de sync en vol qui doit échouer pour le révéler.
                let softLoggedOut = await firstValue(of: old.authState, within: .seconds(60)) { $0 == .softLoggedOut }
                try #require(softLoggedOut == .softLoggedOut, "the session was not soft-logged out within 60 s")

                let new = try await old.reauthenticate(
                    .password(username: configuration.user, password: configuration.password, deviceName: nil)
                )
                current = new

                #expect(new.deviceID == old.deviceID)
                let oldState = await firstValue(of: old.authState, within: .seconds(5)) { _ in true }
                #expect(oldState == .signedOut)
                let stores = storeDirectories(in: directory)
                #expect(stores.count == 1, "stores: \(stores)")

                // Le nouveau jeton expire lui aussi : tout ce qui suit tient dans ses 20 s.
                let newStates = new.sync.state
                await new.sync.start()
                let newState = await waitUntilRunning(newStates)
                try #require(newState == .running, "sync reached \(String(describing: newState))")

                // `room(_:)` ne résout que les salons déjà remontés par la sync.
                let joined = await firstValue(of: new.rooms.list(filter: .joined), within: .seconds(10)) { rooms in
                    rooms.contains { $0.id == roomID }
                }
                try #require(joined != nil, "the encrypted room never appeared in the reauthenticated session")
                let timeline = try await new.rooms.room(roomID).timeline()
                let snapshot = await firstValue(of: timeline.items, within: .seconds(15)) { items in
                    items.contains { $0.message?.body == body }
                }
                let items = try #require(snapshot, "the message sent before the soft logout never appeared")
                let undecryptable = items.filter {
                    if case .unableToDecrypt = $0.kind { return true }
                    return false
                }
                #expect(undecryptable.isEmpty, "undecryptable items: \(undecryptable)")
            } catch {
                let opened = current
                await cleaningUp {
                    await opened.sync.stop()
                    try? await opened.logout()
                }
                throw error
            }

            let opened = current
            await cleaningUp {
                await opened.sync.stop()
                try? await opened.logout()
            }
        }

        /// Les identifiants d'un autre compte sur la session en soft logout : refusés en
        /// `.invalidCredentials`, l'ancienne session reste en soft logout et son store intact —
        /// prouvé par une reconnexion du bon compte, ensuite, sur le même appareil.
        @Test(.timeLimit(.minutes(2)))
        func reauthenticationWithAnotherAccountIsRefused() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let otherUser = try #require(configuration.otherUser, "MCK_HARNESS_OTHER_USER is not exported")
            let otherPassword = try #require(configuration.otherPassword, "MCK_HARNESS_OTHER_PASSWORD is not exported")
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(
                homeserver: configuration.expiringHomeserver, storage: .local(directory: directory))
            let old = try await client.login(
                .password(
                    username: configuration.user, password: configuration.password,
                    deviceName: "Harness (other account)")
            )
            var current: any MatrixSession = old

            do {
                let states = old.sync.state
                await old.sync.start()
                let state = await waitUntilRunning(states)
                try #require(state == .running, "sync reached \(String(describing: state))")
                let softLoggedOut = await firstValue(of: old.authState, within: .seconds(60)) { $0 == .softLoggedOut }
                try #require(softLoggedOut == .softLoggedOut, "the session was not soft-logged out within 60 s")
                let storesBefore = storeDirectories(in: directory)

                let outcome: Result<any MatrixSession, any Error>
                do {
                    outcome = .success(
                        try await old.reauthenticate(
                            .password(username: otherUser, password: otherPassword, deviceName: nil)
                        )
                    )
                } catch {
                    outcome = .failure(error)
                }

                switch outcome {
                case let .success(replacement):
                    await cleaningUp {
                        await replacement.sync.stop()
                        try? await replacement.logout()
                    }
                    Issue.record("reauthenticate succeeded with another account's credentials")
                case let .failure(error):
                    #expect(
                        error as? MatrixError == .authentication(.invalidCredentials),
                        "expected .authentication(.invalidCredentials), got \(error)")
                }

                let oldState = await firstValue(of: old.authState, within: .seconds(5)) { _ in true }
                #expect(oldState == .softLoggedOut)
                let storesAfter = storeDirectories(in: directory)
                #expect(storesAfter == storesBefore, "stores before: \(storesBefore), after: \(storesAfter)")
                #expect(storesAfter.count == 1, "stores: \(storesAfter)")
                // L'appareil créé côté serveur pour l'autre compte (même identifiant) est déconnecté.
                let otherDevices = try await deviceIDs(
                    on: configuration.expiringHomeserver, user: otherUser, password: otherPassword)
                #expect(!otherDevices.contains(old.deviceID.rawValue), "other account's devices: \(otherDevices)")

                // Le store n'a pas été abîmé par la tentative refusée : le bon compte s'y reconnecte.
                let new = try await old.reauthenticate(
                    .password(username: configuration.user, password: configuration.password, deviceName: nil)
                )
                current = new
                #expect(new.userID == old.userID)
                #expect(new.deviceID == old.deviceID)
                #expect(storeDirectories(in: directory) == storesBefore)
            } catch {
                let opened = current
                await cleaningUp {
                    await opened.sync.stop()
                    try? await opened.logout()
                }
                throw error
            }

            let opened = current
            await cleaningUp {
                await opened.sync.stop()
                try? await opened.logout()
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func reauthenticationIsRefusedOutsideSoftLogout() async throws {
            let configuration = try #require(HarnessConfiguration.current)
            let directory = newHarnessDirectory()
            defer { removeDirectory(directory) }

            let client = Matrix.client(
                homeserver: configuration.passwordHomeserver, storage: .local(directory: directory))
            let session = try await client.login(
                .password(username: configuration.user, password: configuration.password, deviceName: "Harness")
            )

            let outcome: Result<any MatrixSession, any Error>
            do {
                outcome = .success(
                    try await session.reauthenticate(
                        .password(username: configuration.user, password: configuration.password, deviceName: nil)
                    )
                )
            } catch {
                outcome = .failure(error)
            }

            switch outcome {
            case let .success(replacement):
                // Succès inattendu : la session rendue détient désormais l'appareil, c'est elle
                // qu'il faut déconnecter avant d'échouer.
                await cleaningUp {
                    await replacement.sync.stop()
                    try? await replacement.logout()
                }
                Issue.record("reauthenticate succeeded outside a soft logout")
            case let .failure(error):
                let isUnexpected = if case .unexpected? = error as? MatrixError { true } else { false }
                #expect(isUnexpected, "expected .unexpected, got \(error)")
            }

            await cleaningUp { try? await session.logout() }
        }
    }
}
