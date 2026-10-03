// Crée, dans un processus à part, le store d'un client 0.2 — sans `crossProcessLockConfig` —, pour
// le cas d'intégration `aStoreCreatedWithoutTheLockIsRestoredWithIt`. Le cas lance cet exécutable,
// attend qu'il se termine, puis restaure le store avec le verrou : la fin du processus garantit que
// le store est fermé avant que le client 0.3 l'ouvre, comme lors d'une vraie mise à jour de
// l'application, qui est un relancement. Avant de se terminer, le seeder rend au store la mise en
// page 0.1–0.3 (répertoire et clé sous l'empreinte du user ID, aucun `storeID`) : le parent
// restaure ainsi un store 0.3 avec le client 0.4.
//
// Tout vient de l'environnement, jamais de la ligne de commande (visible dans `ps`) :
// `MATRIX_TEST_HOMESERVER`, `MATRIX_TEST_USERNAME`, `MATRIX_TEST_PASSWORD` et
// `MATRIX_TEST_SEEDER_APP_GROUP`.
//
// Les secrets (session persistée et clé du store) ne vont pas dans le Keychain mais dans un magasin
// en mémoire, rendu au parent sur stdout — voir ``ExportableSecureStore``. Le mot de passe n'est
// jamais écrit nulle part.
//
// Codes de sortie : 0 succès, 64 environnement incomplet, 1 échec de connexion, 2 sync qui n'a pas
// atteint `.running`, 3 délai global dépassé, 143 `SIGTERM` reçu (du parent, à son propre délai).

import Foundation
import Synchronization
import MatrixClientKit
import MatrixClientKitCore
// Import simple, pas `@testable` : ce que le seeder utilise est en portée `package`, et une cible
// exécutable du package racine est construite aussi par `swift build -c release`, sans testabilité.
import MatrixClientKitRust

enum Seeder {
    /// Préfixe de l'unique ligne lisible par le parent ; tout le reste de stdout est ignoré.
    static let seedLinePrefix = "MCK-LEGACY-SEED "

    /// Délai global, en secondes : couvre aussi un appel du SDK qui ignorerait l'annulation, que
    /// seule la fin du processus interrompt. Inférieur à la borne du parent, pour que l'échec
    /// vienne d'ici, avec un message, plutôt que d'un `SIGTERM` muet.
    static let globalTimeout = 75
}

/// Ce que le parent reçoit : l'identifiant de l'utilisateur et chaque entrée secrète écrite par le
/// client, telle quelle (`Data` encodé en base64 par `JSONEncoder`).
struct LegacySeed: Codable, Sendable {
    let userID: String
    let secrets: [String: Data]
}

/// Magasin de secrets en mémoire, énumérable pour être rendu au parent.
///
/// Pas le Keychain : sur macOS, une entrée du trousseau de session ajoutée par un exécutable n'est
/// lisible sans dialogue que par ce même exécutable. Le processus de test la lirait en bloquant sur
/// une demande d'autorisation, et ne pourrait pas non plus la supprimer (`errSecInvalidOwnerEdit`) —
/// une entrée orpheline bloquerait ensuite tous les cas du même compte. Le parent écrit donc
/// lui-même ces entrées dans le Keychain, sous sa propre identité, comme une application relancée
/// retrouve les siennes.
final class ExportableSecureStore: SecureStore {
    private let entries = Mutex<[String: Data]>([:])

    func data(forKey key: String) throws -> Data? {
        entries.withLock { $0[key] }
    }

    func set(_ data: Data, forKey key: String) throws {
        entries.withLock { $0[key] = data }
    }

    func removeValue(forKey key: String) throws {
        _ = entries.withLock { $0.removeValue(forKey: key) }
    }

    var snapshot: [String: Data] {
        entries.withLock { $0 }
    }
}

/// La ligne du parent, prête dès la connexion réussie : même si la sync échoue ensuite, ou si le
/// délai global ou un `SIGTERM` interrompt le processus, le parent a de quoi déconnecter l'appareil
/// ouvert ici.
enum Report {
    private static let pending = Mutex<LegacySeed?>(nil)

    /// Tenu de l'émission jusqu'à `_exit` : un second ``finish(_:_:)`` concurrent (chemin
    /// principal, délai global, `SIGTERM`) attend ici que le processus se termine, sans jamais
    /// couper une ligne à moitié écrite ni en écrire une seconde.
    private static let exiting = Mutex<Void>(())

    static func prepare(_ seed: LegacySeed) {
        pending.withLock { $0 = seed }
    }

    static func finish(_ code: Int32, _ message: String?) -> Never {
        exiting.withLock { _ -> Never in
            if let seed = pending.withLock({ $0 }), let json = try? JSONEncoder().encode(seed) {
                FileHandle.standardOutput.write(Data(Seeder.seedLinePrefix.utf8) + json + Data("\n".utf8))
            }
            if let message {
                FileHandle.standardError.write(Data("IntegrationLegacySeeder: \(message)\n".utf8))
            }
            _exit(code)
        }
    }
}

/// Termine le processus sans passer par les destructeurs : c'est la fin du processus, pas une
/// fermeture propre du client, qui modélise le relancement — sur iOS, une mise à jour tue
/// l'application. Stdout et stderr sont écrits par `FileHandle`, sans tampon à vider.
func finish(_ code: Int32, _ message: String? = nil) -> Never {
    Report.finish(code, message)
}

func requiredEnvironment(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        finish(64, "missing environment variable \(name)")
    }
    return value
}

/// Même règle que `waitUntilRunning` de la suite : `.terminated` et `.error` sont terminaux,
/// `.idle` et `.offline` ne le sont pas.
func waitUntilRunning(_ states: AsyncStream<SyncState>) async -> SyncState? {
    for await state in states {
        switch state {
        case .running, .terminated, .error:
            return state
        case .idle, .offline:
            continue
        }
    }
    return nil
}

let homeserverValue = requiredEnvironment("MATRIX_TEST_HOMESERVER")
let username = requiredEnvironment("MATRIX_TEST_USERNAME")
let password = requiredEnvironment("MATRIX_TEST_PASSWORD")
let appGroup = requiredEnvironment("MATRIX_TEST_SEEDER_APP_GROUP")
guard let homeserver = URL(string: homeserverValue) else {
    finish(64, "MATRIX_TEST_HOMESERVER is not a URL")
}

DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Seeder.globalTimeout)) {
    finish(3, "timed out after \(Seeder.globalTimeout) s")
}

// Le parent envoie `SIGTERM` à son propre délai : l'action par défaut tuerait le processus sans
// rendre la ligne, donc sans le jeton qui permet de déconnecter l'appareil. Ignoré au niveau du
// processus, le signal n'est plus livré que par cette source, qui passe par ``finish(_:_:)``.
signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
// `@Sendable` explicite : sans lui, la closure écrite dans le code de premier niveau hérite de
// l'isolation `@MainActor`, et son appel depuis la file globale piège à l'exécution (`SIGTRAP`).
terminationSource.setEventHandler { @Sendable in
    finish(143, "terminated by SIGTERM")
}
terminationSource.resume()

let secrets = ExportableSecureStore()
// Client 0.2 : `.unset` ne pose jamais `crossProcessLockConfig` sur le builder. Le restorer est
// gardé pour rendre ensuite au store la mise en page 0.3 (voir plus bas).
let restorer = SessionRestorer(storage: .appGroup(appGroup), secureStore: secrets, lockPolicy: .unset)
let legacy = RustMatrixClient(homeserver: homeserver, restorer: restorer)

let session: any MatrixSession
do {
    session = try await legacy.login(
        .password(username: username, password: password, deviceName: "MatrixClientKit Integration (0.2 store)")
    )
} catch {
    finish(1, "login failed: \(error)")
}
Report.prepare(LegacySeed(userID: session.userID.rawValue, secrets: secrets.snapshot))

// Abonnement posé avant `start()` : le flux de sync ne rejoue pas l'état courant.
let states = session.sync.state
await session.sync.start()
let state = await waitUntilRunning(states)
await session.sync.stop()

// Relu après `stop()` : un rafraîchissement de jeton pendant la sync a pu réécrire la session.
Report.prepare(LegacySeed(userID: session.userID.rawValue, secrets: secrets.snapshot))
guard state == .running else {
    finish(2, "sync reached \(String(describing: state)) instead of .running")
}

// Un client 0.4 range son store sous un `storeID` ; un client 0.3 le rangeait sous l'empreinte
// du user ID, sans `storeID` persisté. Le parent doit restaurer ce second format : la session et
// la clé sont réécrites sous leurs noms 0.3 avant d'être rendues.
do {
    try restorer.downgradeToLegacyLayout()
} catch {
    finish(1, "downgrade to the 0.3 layout failed: \(error)")
}
Report.prepare(LegacySeed(userID: session.userID.rawValue, secrets: secrets.snapshot))
finish(0)
