import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private let persistedHomeserver = URL(string: "https://matrix-client.persisted.example")!

private func makeRestorer() -> SessionRestorer {
    // Racine propre à chaque test : la restauration ramasse les stores orphelins sous sa racine,
    // et ne doit pas toucher à ceux des autres tests.
    SessionRestorer(
        storage: .local(
            directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
        ),
        secureStore: InMemorySecureStore(),
        registry: StoreRegistry()
    )
}

private func persistedSession() -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:persisted.example")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: persistedHomeserver,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func restoringBuildsTheClientForThePersistedHomeserver() async throws {
    let restorer = makeRestorer()
    try restorer.persistence.save(persistedSession())
    var requestedHomeserver: URL?

    do {
        _ = try await restorer.restore { homeserver, _ in
            requestedHomeserver = homeserver
            throw MatrixError.storage(.unavailable)
        }
        Issue.record("la fabrique de client a échoué : la restauration doit relayer l'erreur")
    } catch {
        #expect(error as? MatrixError == .storage(.unavailable))
    }

    // La session appartient au serveur qui l'a émise : aucune autre adresse ne doit être utilisée.
    #expect(requestedHomeserver == persistedHomeserver)
    // Un échec de stockage ne dit rien de la validité de la session : elle est conservée.
    #expect(try restorer.persistence.load() != nil)
}

@Test func restoringWithoutAPersistedSessionBuildsNoClient() async throws {
    let restorer = makeRestorer()
    var clientWasBuilt = false

    let session = try await restorer.restore { _, _ in
        clientWasBuilt = true
        throw MatrixError.storage(.unavailable)
    }

    #expect(session == nil)
    #expect(!clientWasBuilt)
}

@Test func restoringA03SessionOpensTheLegacyStore() async throws {
    let restorer = makeRestorer()
    try restorer.persistence.save(persistedSession())  // sans storeID
    var requested: StoreSegment?

    _ = try? await restorer.restore { _, localStore in
        requested = localStore.segment
        throw MatrixError.storage(.unavailable)
    }

    #expect(requested == .legacy(UserID(rawValue: "@alice:persisted.example")!))
}

/// Crée un store complet (clé et répertoires) sous la racine du restorer.
private func makeStore(_ segment: StoreSegment, for restorer: SessionRestorer) throws -> URL {
    let store = restorer.makeLocalStore(for: segment)
    _ = try store.encryptionKey()
    try store.paths().createDirectoriesIfNeeded()
    return try store.paths().storeDirectory
}

@Test func restoringLeasesThePersistedStoreBeforeSweepingOrphans() async throws {
    let registry = StoreRegistry()
    let restorer = SessionRestorer(
        storage: .local(
            directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
        ),
        secureStore: InMemorySecureStore(),
        registry: registry
    )
    let kept = MatrixSessionData(
        userID: UserID(rawValue: "@alice:persisted.example")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: persistedHomeserver,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native",
        storeID: "kept"
    )
    try restorer.persistence.save(kept)
    let keptDirectory = try makeStore(.session("kept"), for: restorer)
    let orphanDirectory = try makeStore(.session("orphan"), for: restorer)
    var leasedWhileBuilding = false
    var orphanGoneBeforeBuilding = false

    _ = try? await restorer.restore { _, _ in
        leasedWhileBuilding = registry.isLeased(keptDirectory)
        orphanGoneBeforeBuilding = !FileManager.default.fileExists(atPath: orphanDirectory.path)
        throw MatrixError.storage(.unavailable)
    }

    #expect(leasedWhileBuilding)
    #expect(orphanGoneBeforeBuilding)
    #expect(FileManager.default.fileExists(atPath: keptDirectory.path))
}

@Test func upgradingFrom03KeepsTheLegacyStoreAndSweepsOnlyTheOrphan() async throws {
    let registry = StoreRegistry()
    let restorer = SessionRestorer(
        storage: .local(
            directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
        ),
        secureStore: InMemorySecureStore(),
        registry: registry
    )
    // Le disque tel que le laisse la 0.3 : session persistée sans storeID, store et clé sous
    // l'empreinte du user ID — plus un store UUID orphelin, d'une connexion 0.4 abandonnée.
    let persisted = persistedSession()
    try restorer.persistence.save(persisted)
    let legacy = StoreSegment.legacy(persisted.userID)
    let legacyStore = restorer.makeLocalStore(for: legacy)
    let legacyKey = try legacyStore.encryptionKey()
    let legacyDirectory = try makeStore(legacy, for: restorer)
    let legacyPaths = try legacyStore.paths()
    let orphan = StoreSegment.session("orphan")
    let orphanDirectory = try makeStore(orphan, for: restorer)
    var leasedWhileBuilding = false
    var opened: StoreSegment?

    _ = try? await restorer.restore { _, localStore in
        opened = localStore.segment
        leasedWhileBuilding = registry.isLeased(legacyDirectory)
        throw MatrixError.storage(.unavailable)
    }

    #expect(opened == legacy)
    #expect(leasedWhileBuilding)
    #expect(FileManager.default.fileExists(atPath: legacyPaths.dataDirectory.path))
    #expect(FileManager.default.fileExists(atPath: legacyPaths.cacheDirectory.path))
    #expect(try restorer.secureStore.data(forKey: "\(LocalStore.keyPrefix).\(legacy.directoryName)") == legacyKey)
    #expect(!FileManager.default.fileExists(atPath: orphanDirectory.path))
    #expect(try restorer.secureStore.data(forKey: "\(LocalStore.keyPrefix).\(orphan.directoryName)") == nil)
}

@Test func restoringWithoutAPersistedSessionSweepsOrphans() async throws {
    let restorer = makeRestorer()
    let orphanDirectory = try makeStore(.session("orphan"), for: restorer)

    _ = try await restorer.restore { _, _ in throw MatrixError.storage(.unavailable) }

    #expect(!FileManager.default.fileExists(atPath: orphanDirectory.path))
}

@Test func anUnreadablePersistedSessionSweepsNothing() async throws {
    let restorer = makeRestorer()
    let orphanDirectory = try makeStore(.session("orphan"), for: restorer)
    // Charge utile illisible : on ne sait pas quel store la session désigne.
    try restorer.secureStore.set(Data("illisible".utf8), forKey: SessionPersistence.storageKey)

    _ = try? await restorer.restore { _, _ in throw MatrixError.storage(.unavailable) }

    #expect(FileManager.default.fileExists(atPath: orphanDirectory.path))
}

@Test func downgradingToTheLegacyLayoutMovesTheStoreAndItsKeyUnderTheUserDigest() throws {
    let restorer = makeRestorer()
    let modern = MatrixSessionData(
        userID: UserID(rawValue: "@alice:persisted.example")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: persistedHomeserver,
        accessToken: "jeton",
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native",
        storeID: "modern"
    )
    try restorer.persistence.save(modern)
    let modernDirectory = try makeStore(.session("modern"), for: restorer)
    let key = try restorer.makeLocalStore(for: .session("modern")).encryptionKey()

    try restorer.downgradeToLegacyLayout()

    let legacy = StoreSegment.legacy(modern.userID)
    let legacyDirectory = try restorer.makeLocalStore(for: legacy).paths().storeDirectory
    #expect(!FileManager.default.fileExists(atPath: modernDirectory.path))
    #expect(FileManager.default.fileExists(atPath: legacyDirectory.path))
    #expect(try restorer.secureStore.data(forKey: "\(LocalStore.keyPrefix).\(legacy.directoryName)") == key)
    #expect(try restorer.secureStore.data(forKey: "\(LocalStore.keyPrefix).modern") == nil)
    #expect(try restorer.persistence.load()?.storeID == nil)
    #expect(try restorer.persistence.load()?.deviceID == modern.deviceID)
}
