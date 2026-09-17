import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Construit le client persistant d'un utilisateur et restaure la session enregistrée.
///
/// Partagé par ``RustMatrixClient`` et par ``RustMatrixClient/restoreSession(storage:)`` : la
/// restauration n'a besoin que du stockage, puisque l'adresse du homeserver fait partie de la
/// session persistée. Retenu par chaque session qu'il produit, pour que ``sessionDelegate`` vive
/// aussi longtemps qu'elle.
final class SessionRestorer: Sendable {
    let storage: MatrixStorage
    let secureStore: any SecureStore
    let persistence: SessionPersistence

    /// Le SDK s'en sert à chaque rafraîchissement de jeton : un delegate libéré ne persisterait
    /// plus rien, et l'utilisateur serait déconnecté au lancement suivant sans erreur visible.
    let sessionDelegate: SessionDelegate

    convenience init(storage: MatrixStorage) {
        self.init(storage: storage, secureStore: KeychainSecureStore(storage: storage))
    }

    init(storage: MatrixStorage, secureStore: any SecureStore) {
        self.storage = storage
        self.secureStore = secureStore
        let persistence = SessionPersistence(store: secureStore)
        self.persistence = persistence
        self.sessionDelegate = SessionDelegate(persistence: persistence)
    }

    func makeLocalStore(for userID: UserID) -> LocalStore {
        LocalStore(storage: storage, userID: userID, secureStore: secureStore)
    }

    /// Construit le client à store SQLite chiffré d'un utilisateur.
    func makeClient(homeserver: URL, localStore: LocalStore) async throws -> Client {
        do {
            let paths = try localStore.paths()
            try paths.createDirectoriesIfNeeded()

            return try await ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: sessionDelegate)
                // Désactivé par défaut en amont : sans lui, un compte qui ne s'est jamais connecté
                // ailleurs n'a pas d'identité cross-signing, et la vérification échoue toujours
                // (spec 0.2, §2.8). Uniquement ici, jamais sur le client de poignée de main : son
                // store en mémoire perdrait les clés privées aussitôt créées.
                .autoEnableCrossSigning(autoEnableCrossSigning: true)
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

    func restore() async throws -> (any MatrixClientKitCore.MatrixSession)? {
        try await restore(makeClient: { homeserver, localStore in
            try await self.makeClient(homeserver: homeserver, localStore: localStore)
        })
    }

    /// - Parameter makeClient: fabrique du client. Couture de test : `Client` est une classe FFI
    ///   qu'un test ne peut pas construire, mais il peut vérifier l'adresse demandée.
    func restore(
        makeClient: (URL, LocalStore) async throws -> Client
    ) async throws -> (any MatrixClientKitCore.MatrixSession)? {
        guard let data = try persistence.load() else { return nil }

        let localStore = makeLocalStore(for: data.userID)
        // L'adresse persistée fait foi : c'est celle du serveur qui a émis la session, résolue
        // lors de la connexion.
        let client = try await makeClient(data.homeserverURL, localStore)
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            return try await RustMatrixSession.make(client: client, restorer: self, localStore: localStore)
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
                try? persistence.clear()
                try? localStore.purge()
            }

            throw mapped
        }
    }
}
