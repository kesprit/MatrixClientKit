import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let restorer: SessionRestorer

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.restorer = SessionRestorer(storage: storage)
    }

    /// Couture de test : un restorer à politique de verrou choisie, pour reproduire un client 0.2
    /// dans la suite d'intégration. Portée `package` pour l'exécutable `IntegrationLegacySeeder`.
    package init(homeserver: URL, restorer: SessionRestorer) {
        self.homeserver = homeserver
        self.restorer = restorer
    }

    /// Restaure la session persistée sans connaître l'adresse du homeserver, enregistrée avec elle.
    public static func restoreSession(storage: MatrixStorage) async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await SessionRestorer(storage: storage).restore()
    }

    /// Ouvre une session.
    ///
    /// La connexion se fait en deux temps, et c'est délibéré. Le store SQLite doit être **unique
    /// par utilisateur** (contrainte amont), donc son chemin dépend de l'identifiant — que le
    /// serveur ne révèle qu'une fois la connexion faite, alors que `ClientBuilder.build()` exige
    /// le chemin avant. La poignée de main se fait donc sur un client à store en mémoire, qui
    /// n'écrit rien sur disque ; l'identifiant obtenu détermine le chemin et la clé du vrai
    /// client, dans lequel la session est ensuite restaurée. Aucun store n'est jamais créé sous
    /// un chemin provisoire qu'il faudrait déplacer ensuite.
    ///
    /// Le vrai client est construit avec l'adresse que la session rapporte, comme à chaque
    /// restauration ultérieure : une seule source de vérité pour l'adresse d'une session.
    public func login(_ credentials: Credentials) async throws -> any MatrixClientKitCore.MatrixSession {
        do {
            let handshake = try await makeHandshakeClient()

            switch credentials {
            case let .password(username, password, deviceName):
                try await handshake.login(
                    username: username,
                    password: password,
                    initialDeviceName: deviceName,
                    deviceId: nil
                )
            }

            let data = try SessionMapper.sessionData(from: handshake.session())
            let localStore = restorer.makeLocalStore(for: data.userID)
            let client = try await restorer.makeClient(homeserver: data.homeserverURL, localStore: localStore)
            try await client.restoreSession(session: SessionMapper.session(from: data))

            try restorer.persistence.save(data)
            return try await RustMatrixSession.make(client: client, restorer: restorer, localStore: localStore)
        } catch {
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    public func restoreSession() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await restorer.restore()
    }

    /// Client éphémère servant uniquement à la poignée de main de connexion.
    ///
    /// Store en mémoire : rien n'est écrit sur disque avant que l'identifiant de l'utilisateur ne
    /// soit connu, donc aucun store orphelin ne subsiste si la connexion échoue.
    private func makeHandshakeClient() async throws -> Client {
        do {
            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: restorer.sessionDelegate)
                .inMemoryStore()
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
