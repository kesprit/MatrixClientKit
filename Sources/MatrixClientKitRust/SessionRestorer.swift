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
    /// Couture de test : `.unset` reproduit un client 0.2, qui n'appelait jamais
    /// `crossProcessLockConfig`. Sert uniquement au cas d'intégration qui restaure un tel store.
    enum LockPolicy: Sendable {
        case automatic
        case unset
    }

    let storage: MatrixStorage
    let secureStore: any SecureStore
    let persistence: SessionPersistence
    let role: ClientRole
    let lockPolicy: LockPolicy

    /// Le SDK s'en sert à chaque rafraîchissement de jeton : un delegate libéré ne persisterait
    /// plus rien, et l'utilisateur serait déconnecté au lancement suivant sans erreur visible.
    let sessionDelegate: SessionDelegate

    convenience init(storage: MatrixStorage, role: ClientRole = .application, lockPolicy: LockPolicy = .automatic) {
        self.init(
            storage: storage,
            secureStore: KeychainSecureStore(storage: storage),
            role: role,
            lockPolicy: lockPolicy
        )
    }

    init(
        storage: MatrixStorage,
        secureStore: any SecureStore,
        role: ClientRole = .application,
        lockPolicy: LockPolicy = .automatic
    ) {
        self.storage = storage
        self.secureStore = secureStore
        self.role = role
        self.lockPolicy = lockPolicy
        let persistence = SessionPersistence(store: secureStore)
        self.persistence = persistence
        self.sessionDelegate = SessionDelegate(persistence: persistence)
    }

    /// Le verrou à poser sur le builder, ou `nil` pour ne pas l'appeler.
    func lockConfiguration() throws -> CrossProcessLockConfig? {
        switch lockPolicy {
        case .automatic:
            return try CrossProcessLock.configuration(for: storage, role: role)
        case .unset:
            return nil
        }
    }

    func makeLocalStore(for userID: UserID) -> LocalStore {
        LocalStore(storage: storage, userID: userID, secureStore: secureStore)
    }

    /// Construit le client à store SQLite chiffré d'un utilisateur.
    func makeClient(homeserver: URL, localStore: LocalStore) async throws -> Client {
        do {
            let paths = try localStore.paths()
            try paths.createDirectoriesIfNeeded()

            var builder = ClientBuilder()
                .homeserverUrl(url: homeserver.absoluteString)
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: sessionDelegate)
                // Désactivé par défaut en amont : sans lui, un compte qui ne s'est jamais connecté
                // ailleurs n'a pas d'identité cross-signing, et la vérification échoue toujours
                // (spec 0.2, §2.8). Uniquement ici, jamais sur le client de poignée de main : son
                // store en mémoire perdrait les clés privées aussitôt créées. Jamais non plus dans
                // l'extension : amorcer une identité est une écriture de compte réservée à
                // l'application (spec 0.3, §7).
                .autoEnableCrossSigning(autoEnableCrossSigning: role == .application)
                .sqliteStore(
                    config: SqliteStoreBuilder(
                        dataPath: paths.dataDirectory.path,
                        cachePath: paths.cacheDirectory.path
                    )
                    .key(key: try localStore.encryptionKey())
                )
            if let lock = try lockConfiguration() {
                builder = builder.crossProcessLockConfig(crossProcessLockConfig: lock)
            }
            return try await builder.build()
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
