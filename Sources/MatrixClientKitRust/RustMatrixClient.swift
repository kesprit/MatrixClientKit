import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Implémentation de ``MatrixClient`` adossée au SDK Rust.
public final class RustMatrixClient: MatrixClientKitCore.MatrixClient {
    public let homeserver: URL

    private let storage: MatrixStorage
    private let secureStore: any SecureStore
    private let persistence: SessionPersistence

    public init(homeserver: URL, storage: MatrixStorage) {
        self.homeserver = homeserver
        self.storage = storage
        let secureStore = KeychainSecureStore(storage: storage)
        self.secureStore = secureStore
        self.persistence = SessionPersistence(store: secureStore)
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
            let localStore = makeLocalStore(for: data.userID)
            let client = try await makeClient(localStore: localStore)
            try await client.restoreSession(session: SessionMapper.session(from: data))

            try await persistence.save(data)
            return try await RustMatrixSession.make(
                client: client,
                persistence: persistence,
                localStore: localStore
            )
        } catch {
            throw ErrorMapper.mapAuthentication(error)
        }
    }

    public func restoreSession() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        guard let data = try await persistence.load() else { return nil }

        let localStore = makeLocalStore(for: data.userID)
        let client = try await makeClient(localStore: localStore)
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            return try await RustMatrixSession.make(
                client: client,
                persistence: persistence,
                localStore: localStore
            )
        } catch {
            let mapped = ErrorMapper.mapAuthentication(error)

            // Une authentification refusée signifie que la session persistée est morte : la
            // conserver ferait échouer chaque lancement à l'identique, sans qu'aucune API
            // publique ne permette de l'effacer avant une nouvelle connexion réussie. Une panne
            // réseau, de stockage ou serveur, elle, ne dit rien sur la validité de la session —
            // l'effacer déconnecterait l'utilisateur à chaque démarrage hors ligne.
            //
            // Le store local part avec elle : rattaché à une session morte, il ne sera plus
            // jamais rouvert, et laisser sur disque un store crypto inutilisable est exactement
            // ce que la purge au logout existe pour éviter.
            if case .authentication = mapped {
                try? await persistence.clear()
                try? localStore.purge()
            }

            throw mapped
        }
    }

    private func makeLocalStore(for userID: UserID) -> LocalStore {
        LocalStore(storage: storage, userID: userID, secureStore: secureStore)
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
                .inMemoryStore()
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    private func makeClient(localStore: LocalStore) async throws -> Client {
        do {
            let paths = try localStore.paths()
            try paths.createDirectoriesIfNeeded()

            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .sqliteStore(
                    config: SqliteStoreBuilder(
                        dataPath: paths.dataDirectory.path,
                        cachePath: paths.cacheDirectory.path
                    )
                    .key(key: try localStore.encryptionKey())
                )
                .build()
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
