// Pilotage de l'exécutable `IntegrationLegacySeeder` (Tests/IntegrationLegacySeeder), qui crée un
// store 0.2 dans un processus à part pour ``IntegrationTests/NotificationTests``. macOS uniquement :
// `Foundation.Process` n'existe pas sur iOS, où la suite doit tout de même compiler.
#if os(macOS)
    import Testing
    import Foundation

    /// Ce que le seeder rend sur sa ligne `MCK-LEGACY-SEED` : même forme JSON que le `LegacySeed` de
    /// l'exécutable, qui n'est pas importable ici.
    struct LegacySeed: Decodable, Sendable {
        let userID: String
        /// Entrées secrètes écrites par le client 0.2 (session persistée, clé du store), par clé.
        let secrets: [String: Data]
    }

    /// Issue d'une exécution du seeder.
    struct LegacySeederRun: Sendable {
        /// Code de sortie, ou numéro du signal si le processus a été tué.
        let status: Int32
        /// `true` si le parent a dû tuer le seeder faute de fin dans le délai.
        let timedOut: Bool
        /// Présent dès que la connexion a réussi, même si la sync a échoué ensuite.
        let seed: LegacySeed?
        let standardError: String

        var succeeded: Bool { !timedOut && status == 0 && seed != nil }

        var failureDescription: String {
            let reason = timedOut ? "timed out" : "exited with status \(status)"
            return "IntegrationLegacySeeder \(reason); stderr: \(standardError)"
        }
    }

    /// Repère du bundle de test pour ``legacySeederURL()``.
    private final class LegacySeederLocator {}

    /// Emplacement de l'exécutable du seeder.
    ///
    /// SwiftPM (`swift test`) comme Xcode placent le bundle `.xctest` et les exécutables du package dans
    /// le même répertoire de produits ; la dépendance de la suite sur la cible garantit qu'il y est
    /// construit. `Bundle(for:)` résout l'image qui contient réellement ce code (via `dladdr`), quel que
    /// soit le processus hôte — `xctest`, `swiftpm-testing-helper` ou l'agent de Xcode —, là où
    /// `Bundle.main` désignerait l'hôte et `#filePath` les sources.
    func legacySeederURL() throws -> URL {
        let products = Bundle(for: LegacySeederLocator.self).bundleURL.deletingLastPathComponent()
        let url = products.appending(path: "IntegrationLegacySeeder")
        try #require(
            FileManager.default.isExecutableFile(atPath: url.path),
            "IntegrationLegacySeeder not found at \(url.path): build it with `swift build --build-tests`"
        )
        return url
    }

    /// Lit un descripteur jusqu'à sa fin sur un fil de Dispatch, pour ne bloquer aucun fil du pool
    /// coopératif. La fin arrive quand le seeder se termine : `Process` ferme dans le parent
    /// l'extrémité d'écriture des `Pipe` au lancement.
    private func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    /// Lance le seeder sur l'App Group `appGroup` et attend sa fin, au plus `timeout`.
    ///
    /// L'environnement du test est hérité tel quel (les `MATRIX_TEST_*`), plus l'App Group : aucun
    /// secret ne passe par la ligne de commande. Stdout et stderr sont lus en continu, pour qu'un
    /// seeder bavard ne bloque jamais sur un tube plein. Passé le délai, le seeder reçoit `SIGTERM`
    /// puis, s'il survit, `SIGKILL` : un appel du SDK qui ignore l'annulation ne retient pas le test.
    func runLegacySeeder(appGroup: String, timeout: Duration) async throws -> LegacySeederRun {
        let process = Process()
        process.executableURL = try legacySeederURL()
        var environment = ProcessInfo.processInfo.environment
        environment["MATRIX_TEST_SEEDER_APP_GROUP"] = appGroup
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice

        let (exits, exitContinuation) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exitContinuation.finish() }
        try process.run()
        let pid = process.processIdentifier

        async let outputData = readToEnd(output.fileHandleForReading)
        async let errorData = readToEnd(errors.fileHandleForReading)

        // Rend `true` s'il a dû tuer le seeder. Annulé dès la fin du processus, avant d'avoir tiré.
        let watchdog = Task.detached { () -> Bool in
            do { try await Task.sleep(for: timeout) } catch { return false }
            kill(pid, SIGTERM)
            do { try await Task.sleep(for: .seconds(5)) } catch { return true }
            kill(pid, SIGKILL)
            return true
        }

        // L'annulation du test (`.timeLimit`) tue aussi le seeder, sans quoi les lectures ci-dessous
        // l'attendraient jusqu'à son propre délai.
        await withTaskCancellationHandler {
            for await _ in exits {}
        } onCancel: {
            kill(pid, SIGKILL)
        }
        watchdog.cancel()
        let timedOut = await watchdog.value

        let standardOutput = String(decoding: await outputData, as: UTF8.self)
        let standardError = String(decoding: await errorData, as: UTF8.self)
        let prefix = "MCK-LEGACY-SEED "
        let seed = standardOutput.split(separator: "\n")
            .first { $0.hasPrefix(prefix) }
            .flatMap { try? JSONDecoder().decode(LegacySeed.self, from: Data($0.dropFirst(prefix.count).utf8)) }

        return LegacySeederRun(
            status: process.isRunning ? -1 : process.terminationStatus,
            timedOut: timedOut,
            seed: seed,
            standardError: standardError
        )
    }
#endif
