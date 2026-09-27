import Testing
import Foundation
import MatrixClientKit

/// Clé de récupération au bon format mais délibérément fausse.
private let wrongRecoveryKey = "EsTc 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000 0000"

private func isIncomingRequest(_ state: SessionVerificationState) -> Bool {
    if case .incomingRequest = state { return true }
    return false
}

private func isComparing(_ state: SessionVerificationState) -> Bool {
    if case .comparing = state { return true }
    return false
}

extension IntegrationTests {
    // Sérialisée avec le reste de ``IntegrationTests`` : tous les cas utilisent le même compte,
    // l'un d'eux révoque toutes ses sessions, et les autres suites d'intégration partagent ce même
    // compte et la même entrée Keychain.
    @Suite
    struct EncryptionAndSessionTests {

        @Test(.timeLimit(.minutes(1)))
        func restoringNeedsOnlyTheStorage() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            var signedIn: (session: any MatrixSession, directory: URL)? = try await signIn(
                configuration, deviceName: "MatrixClientKit Integration (restore)")
            let directory = try #require(signedIn?.directory)
            let userID = try #require(signedIn?.session.userID)
            await signedIn?.session.sync.stop()

            // Libère le premier client : deux clients ouverts sur le même store SQLite se disputeraient
            // ses fichiers.
            signedIn = nil

            let restored = try #require(try await Matrix.restoreSession(storage: .local(directory: directory)))
            #expect(restored.userID == userID)

            await cleaningUp {
                try? await restored.logout()
                removeDirectory(directory)
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func startingSyncTwiceKeepsItRunning() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let integration = makeClient(configuration)
            let directory = integration.directory
            let session = try await integration.client.login(
                .password(
                    username: configuration.username,
                    password: configuration.password,
                    deviceName: "MatrixClientKit Integration (sync)"
                )
            )

            // Deux abonnements posés avant le premier `start()` : le flux de sync ne rejoue pas
            // l'état courant, donc les ouvrir après aurait manqué la transition vers `.running` que
            // ce test doit justement observer.
            let states = session.sync.state
            let untilRunning = session.sync.state
            let observed = Task {
                var collected: [SyncState] = []
                for await state in states {
                    collected.append(state)
                }
                return collected
            }

            await session.sync.start()
            _ = await firstValue(of: untilRunning) { $0 == .running }

            // Second démarrage pendant que la sync tourne déjà : sans effet d'après le contrat
            // documenté sur `SyncController.start()`.
            await session.sync.start()
            try await Task.sleep(for: .seconds(3))
            observed.cancel()
            let collected = await observed.value

            #expect(collected.contains(.running))
            let runningIndex = try #require(collected.firstIndex(of: .running))
            // Un second démarrage qui relancerait la sync repasserait par un état d'arrêt après le
            // premier `.running`.
            let afterRunning = collected[runningIndex...]
            #expect(!afterRunning.contains(.idle))
            #expect(!afterRunning.contains(.terminated))

            await cleaningUp {
                await session.sync.stop()
                try? await session.logout()
                removeDirectory(directory)
            }
        }

        @Test(.timeLimit(.minutes(2)))
        func aServerSideLogoutSignsTheSessionOutAndErasesItsStore() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let (session, directory) = try await signIn(
                configuration, deviceName: "MatrixClientKit Integration (server logout)")
            #expect(!sqliteFiles(in: directory).isEmpty, "le store doit exister avant la déconnexion")

            let authStates = session.authState
            let token = try await rawAccessToken(configuration)
            try await logOutEverywhere(configuration, accessToken: token)

            // La sync suivante reçoit M_UNKNOWN_TOKEN : le SDK appelle le delegate, la session purge
            // puis publie `.signedOut`.
            #expect(await firstValue(of: authStates) { $0 == .signedOut } == .signedOut)
            #expect(sqliteFiles(in: directory).isEmpty)

            await cleaningUp { removeDirectory(directory) }
        }

        @Test(.enabled(if: IntegrationConfiguration.hasRecoveryKey), .timeLimit(.minutes(2)))
        func aWrongRecoveryKeyIsRejectedAndTheRightOneVerifiesTheDevice() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let recoveryKey = try #require(configuration.recoveryKey)
            let (session, directory) = try await signIn(
                configuration, deviceName: "MatrixClientKit Integration (recovery)")

            _ = await firstValue(of: session.encryption.recoveryState) { $0 != .unknown }

            // Épingle le mappage de spec §7.1, fondé sur le message amont.
            await #expect(throws: MatrixError.encryption(.invalidRecoveryKey)) {
                try await session.encryption.recover(with: wrongRecoveryKey)
            }

            try await session.encryption.recover(with: recoveryKey)
            #expect(await firstValue(of: session.encryption.verificationStatus) { $0 == .verified } == .verified)
            #expect(await firstValue(of: session.encryption.recoveryState) { $0 == .enabled } == .enabled)

            await cleaningUp {
                await session.sync.stop()
                try? await session.logout()
                removeDirectory(directory)
            }
        }

        @Test(.enabled(if: IntegrationConfiguration.hasRecoveryKey), .timeLimit(.minutes(3)))
        func anotherDeviceVerifiesThisOne() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let recoveryKey = try #require(configuration.recoveryKey)

            // A : appareil vérifié grâce à la clé de récupération.
            let (verified, verifiedDirectory) = try await signIn(
                configuration, deviceName: "MatrixClientKit Integration (A)")
            _ = await firstValue(of: verified.encryption.recoveryState) { $0 != .unknown }
            try await verified.encryption.recover(with: recoveryKey)
            _ = await firstValue(of: verified.encryption.verificationStatus) { $0 == .verified }

            // B : nouvel appareil à vérifier. Les deux sessions partagent l'entrée Keychain de session
            // persistée (une par service) : B écrase celle de A, sans effet ici puisque rien n'est
            // restauré.
            let (newcomer, newcomerDirectory) = try await signIn(
                configuration, deviceName: "MatrixClientKit Integration (B)")
            _ = await firstValue(of: newcomer.encryption.verificationStatus) { $0 == .unverified }
            #expect(try await newcomer.encryption.hasDevicesToVerifyAgainst())

            // A obtient son contrôleur de vérification sur le changement d'état qui vient de le rendre
            // vérifié ; on lui laisse le temps d'y poser son delegate avant que la demande n'arrive.
            try await Task.sleep(for: .seconds(2))

            let onA = verified.encryption.sessionVerification
            let onB = newcomer.encryption.sessionVerification

            try await onB.requestVerification()
            _ = await firstValue(of: onA.state, where: isIncomingRequest)
            try await onA.accept()
            _ = await firstValue(of: onB.state) { $0 == .ready }
            try await onB.startSAS()

            let shownOnB = await firstValue(of: onB.state, where: isComparing)
            let shownOnA = await firstValue(of: onA.state, where: isComparing)
            // C'est ce que l'utilisateur compare : les deux appareils doivent montrer la même chose.
            #expect(shownOnA != nil)
            #expect(shownOnA == shownOnB)

            try await onA.approve()
            try await onB.approve()
            #expect(await firstValue(of: onB.state) { $0.isFinished } == .verified)
            #expect(await firstValue(of: newcomer.encryption.verificationStatus) { $0 == .verified } == .verified)

            await cleaningUp {
                await verified.sync.stop()
                await newcomer.sync.stop()
                try? await newcomer.logout()
                try? await verified.logout()
                removeDirectory(verifiedDirectory)
                removeDirectory(newcomerDirectory)
            }
        }

        @Test(.enabled(if: IntegrationConfiguration.hasFreshAccount), .timeLimit(.minutes(1)))
        func aFreshAccountGetsACrossSigningIdentityAtSignIn() async throws {
            let configuration = try #require(IntegrationConfiguration.current)
            let (session, directory) = try await signIn(
                configuration,
                username: configuration.freshUsername,
                password: configuration.freshPassword,
                deviceName: "MatrixClientKit Integration (fresh)"
            )

            // Sans `autoEnableCrossSigning`, l'état resterait `.unverified` : aucune identité à signer.
            #expect(await firstValue(of: session.encryption.verificationStatus) { $0 == .verified } == .verified)

            await cleaningUp {
                await session.sync.stop()
                try? await session.logout()
                removeDirectory(directory)
            }
        }
    }
}
