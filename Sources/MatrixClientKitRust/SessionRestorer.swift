import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Comment le builder désigne le homeserver.
enum ClientTarget: Sendable, Hashable {
    /// Adresse déjà résolue : celle d'une session persistée, ou d'un client créé par URL.
    case homeserver(URL)
    /// Nom de serveur, URL ou user ID à résoudre par `.well-known` (découverte, QR scanné).
    case serverName(String)
}

/// Construit le client persistant d'un utilisateur et restaure la session enregistrée.
///
/// Partagé par ``RustMatrixClient`` et par ``RustMatrixClient/restoreSession(storage:)`` : la
/// restauration n'a besoin que du stockage, puisque l'adresse du homeserver fait partie de la
/// session persistée. Retenu par chaque session qu'il produit, pour que ``sessionDelegate`` vive
/// aussi longtemps qu'elle.
package final class SessionRestorer: Sendable {
    /// Couture de test : `.unset` reproduit un client 0.2, qui n'appelait jamais
    /// `crossProcessLockConfig`. Sert uniquement au cas d'intégration qui restaure un tel store.
    ///
    /// Portée `package` (comme le type et son initialiseur désigné) pour l'exécutable
    /// `IntegrationLegacySeeder`, qui doit compiler sans `@testable` en release.
    package enum LockPolicy: Sendable {
        case automatic
        case unset
    }

    let storage: MatrixStorage
    let secureStore: any SecureStore
    let persistence: SessionPersistence
    let role: ClientRole
    let lockPolicy: LockPolicy
    /// Les baux de ce processus ; `.shared` hors des tests, pour que tous les stockages voient
    /// les mêmes stores vivants.
    let registry: StoreRegistry

    /// Le SDK s'en sert à chaque rafraîchissement de jeton : un delegate libéré ne persisterait
    /// plus rien, et l'utilisateur serait déconnecté au lancement suivant sans erreur visible.
    let sessionDelegate: SessionDelegate

    convenience init(
        storage: MatrixStorage,
        role: ClientRole = .application,
        lockPolicy: LockPolicy = .automatic,
        registry: StoreRegistry = .shared
    ) {
        self.init(
            storage: storage,
            secureStore: KeychainSecureStore(storage: storage),
            role: role,
            lockPolicy: lockPolicy,
            registry: registry
        )
    }

    package init(
        storage: MatrixStorage,
        secureStore: any SecureStore,
        role: ClientRole = .application,
        lockPolicy: LockPolicy = .automatic,
        registry: StoreRegistry = .shared
    ) {
        self.storage = storage
        self.secureStore = secureStore
        self.role = role
        self.lockPolicy = lockPolicy
        self.registry = registry
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

    func makeLocalStore(for segment: StoreSegment) -> LocalStore {
        LocalStore(storage: storage, segment: segment, secureStore: secureStore)
    }

    var sweeper: OrphanedStoreSweeper {
        OrphanedStoreSweeper(storage: storage, secureStore: secureStore, registry: registry)
    }

    /// Ramasse les stores orphelins, sauf dans l'extension (spec 0.3, §7 ; spec 0.4, §5.4).
    func sweepOrphans(keeping kept: StoreSegment?) {
        guard role == .application else { return }
        sweeper.sweep(keeping: kept)
    }

    /// Construit le client à store SQLite chiffré d'un utilisateur.
    func makeClient(homeserver: URL, localStore: LocalStore) async throws -> Client {
        try await makeClient(target: .homeserver(homeserver), localStore: localStore)
    }

    /// Construit le client sur le store SQLite chiffré de `localStore`, pour un homeserver résolu
    /// ou à résoudre.
    func makeClient(target: ClientTarget, localStore: LocalStore) async throws -> Client {
        do {
            let paths = try localStore.paths()
            // La clé avant les répertoires : dans l'extension, une clé absente (déconnexion en
            // cours) doit échouer sans rien recréer sur disque.
            let key = try localStore.encryptionKey(createIfMissing: role == .application)
            try paths.createDirectoriesIfNeeded()

            var builder: ClientBuilder
            switch target {
            case let .homeserver(url):
                builder = ClientBuilder().homeserverUrl(url: url.absoluteString)
            case let .serverName(name):
                builder = ClientBuilder().serverNameOrHomeserverUrl(serverNameOrUrl: name)
            }
            builder =
                builder
                .slidingSyncVersionBuilder(versionBuilder: .discoverNative)
                .setSessionDelegate(sessionDelegate: sessionDelegate)
                // Désactivé par défaut en amont : sans lui, un compte qui ne s'est jamais connecté
                // ailleurs n'a pas d'identité cross-signing, et la vérification échoue toujours
                // (spec 0.2, §2.8). Uniquement sur un store SQLite : un store en mémoire perdrait
                // les clés privées aussitôt créées. Jamais dans l'extension : amorcer une identité
                // est une écriture de compte réservée à l'application (spec 0.3, §7).
                .autoEnableCrossSigning(autoEnableCrossSigning: role == .application)
                .sqliteStore(
                    config: SqliteStoreBuilder(
                        dataPath: paths.dataDirectory.path,
                        cachePath: paths.cacheDirectory.path
                    )
                    .key(key: key)
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
        // Une lecture en échec ne ramasse rien : on ne sait pas quel store la session persistée
        // désigne, et le ramassage pourrait l'emporter.
        guard let data = try persistence.load() else {
            sweepOrphans(keeping: nil)
            return nil
        }

        let localStore = makeLocalStore(for: StoreSegment(data))
        // Le bail avant le ramassage et avant le client : un ramassage concurrent (une connexion
        // dans ce processus) ne doit jamais emporter le store qu'on s'apprête à ouvrir.
        let lease = registry.lease(try localStore.paths())
        sweepOrphans(keeping: localStore.segment)

        // L'adresse persistée fait foi : c'est celle du serveur qui a émis la session, résolue
        // lors de la connexion.
        let client = try await makeClient(data.homeserverURL, localStore)
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            return try await RustMatrixSession.make(
                client: client,
                restorer: self,
                localStore: localStore,
                lease: lease
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
                try? persistence.clear()
                try? localStore.purge()
            }

            throw mapped
        }
    }

    /// Couture de test, pour l'exécutable `IntegrationLegacySeeder` uniquement : rend à la session
    /// persistée la mise en page d'un store 0.1–0.3 — répertoire et entrée Keychain sous
    /// l'empreinte du user ID, aucun `storeID` persisté. Le renommage garde les descripteurs SQLite
    /// ouverts valides (même volume) ; le seeder se termine juste après.
    package func downgradeToLegacyLayout() throws {
        guard let data = try persistence.load(), let storeID = data.storeID else { return }
        let modern = makeLocalStore(for: .session(storeID))
        let legacy = makeLocalStore(for: .legacy(data.userID))
        try FileManager.default.moveItem(at: modern.paths().storeDirectory, to: legacy.paths().storeDirectory)
        if let key = try secureStore.data(forKey: "\(LocalStore.keyPrefix).\(storeID)") {
            try secureStore.set(
                key, forKey: "\(LocalStore.keyPrefix).\(StoreSegment.legacy(data.userID).directoryName)")
            try secureStore.removeValue(forKey: "\(LocalStore.keyPrefix).\(storeID)")
        }
        try persistence.save(
            MatrixSessionData(
                userID: data.userID, deviceID: data.deviceID, homeserverURL: data.homeserverURL,
                accessToken: data.accessToken, refreshToken: data.refreshToken, oauthData: data.oauthData,
                slidingSyncVersion: data.slidingSyncVersion, storeID: nil
            )
        )
    }

    /// Ouvre la session persistée pour résoudre des notifications, sans sync.
    ///
    /// Contrairement à ``restore()``, une authentification refusée n'efface rien : c'est à
    /// l'application, au prochain lancement, de constater la session morte et de nettoyer. Une
    /// extension qui purgerait le store pendant que l'application l'utilise le corromprait.
    func makeNotificationResolver() async throws -> RustNotificationResolver {
        try await makeNotificationResolver { homeserver, localStore in
            try await self.makeClient(homeserver: homeserver, localStore: localStore)
        }
    }

    /// - Parameter makeClient: fabrique du client. Couture de test : `Client` est une classe FFI
    ///   qu'un test ne peut pas construire, mais il peut vérifier l'adresse demandée.
    func makeNotificationResolver(
        makeClient: (URL, LocalStore) async throws -> Client
    ) async throws -> RustNotificationResolver {
        // Échoue avant toute lecture pour un stockage qu'une extension ne peut pas atteindre.
        _ = try lockConfiguration()
        guard let data = try persistence.load() else {
            throw MatrixError.authentication(.missingToken)
        }

        let localStore = makeLocalStore(for: StoreSegment(data))
        let client = try await makeClient(data.homeserverURL, localStore)
        do {
            try await client.restoreSession(session: SessionMapper.session(from: data))
            let notificationClient = try await client.notificationClient(processSetup: .multipleProcesses)
            return RustNotificationResolver(notificationClient: notificationClient, client: client, restorer: self)
        } catch {
            throw ErrorMapper.mapAuthentication(error)
        }
    }
}
