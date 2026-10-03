import Testing
import Foundation
import MatrixRustSDK
@testable import MatrixClientKitRust
import MatrixClientKitCore

private func makeRestorer(root: URL, registry: StoreRegistry = StoreRegistry()) -> SessionRestorer {
    SessionRestorer(storage: .local(directory: root), secureStore: InMemorySecureStore(), registry: registry)
}

private func newRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
}

@Test func aNewAttemptPreparesAFreshLeasedStore() throws {
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: newRoot(), registry: registry)
    let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)

    guard case .session = store.segment else {
        Issue.record("segment legacy pour une connexion neuve")
        return
    }
    let directory = try store.localStore.paths().storeDirectory
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(registry.isLeased(directory))
    withExtendedLifetime(store) {}
}

@Test func discardingANewAttemptErasesItsStoreAndLease() throws {
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: newRoot(), registry: registry)
    let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)
    let directory = try store.localStore.paths().storeDirectory

    store.discard()

    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(!registry.isLeased(directory))
    #expect(try restorer.secureStore.data(forKey: "\(LocalStore.keyPrefix).\(store.segment.directoryName)") == nil)
}

@Test func discardingAReauthenticationKeepsTheStore() throws {
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: newRoot(), registry: registry)
    let existing = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)
    let reuse = try LoginAttemptStore.prepare(restorer: restorer, reusing: existing.segment)
    let directory = try reuse.localStore.paths().storeDirectory

    reuse.discard()

    // Le store appartient toujours à la session remplacée.
    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(registry.isLeased(directory))  // bail de `existing`
    // Le bail de `existing` doit vivre jusqu'ici : une valeur jamais relue peut être libérée tôt.
    withExtendedLifetime(existing) {}
}

@Test func aFailedClientBuildLeavesNothingBehind() async throws {
    let root = newRoot()
    let registry = StoreRegistry()
    let restorer = makeRestorer(root: root, registry: registry)

    await #expect(throws: MatrixError.network(.offline)) {
        _ = try await LoginAttempt.begin(
            restorer: restorer,
            target: .homeserver(URL(string: "https://x.org")!),
            reusing: nil
        ) { _, _ in
            throw MatrixError.network(.offline)
        }
    }

    let stores =
        (try? FileManager.default.contentsOfDirectory(atPath: StoragePaths.root(for: .local(directory: root)).path))
        ?? []
    #expect(stores.isEmpty)
}

@Test func beginningAnAttemptSweepsOrphans() async throws {
    let root = newRoot()
    let restorer = makeRestorer(root: root)
    let orphan = LocalStore(
        storage: .local(directory: root),
        segment: .session("orphan"),
        secureStore: restorer.secureStore
    )
    _ = try orphan.encryptionKey()
    try orphan.paths().createDirectoriesIfNeeded()

    _ = try? await LoginAttempt.begin(
        restorer: restorer,
        target: .homeserver(URL(string: "https://x.org")!),
        reusing: nil
    ) { _, _ in
        throw MatrixError.network(.offline)
    }

    #expect(!FileManager.default.fileExists(atPath: try orphan.paths().storeDirectory.path))
}

@Test func theExtensionNeverSweeps() throws {
    let root = newRoot()
    let restorer = SessionRestorer(
        storage: .local(directory: root),
        secureStore: InMemorySecureStore(),
        role: .notificationExtension,
        registry: StoreRegistry()
    )
    let orphan = LocalStore(
        storage: .local(directory: root),
        segment: .session("orphan"),
        secureStore: restorer.secureStore
    )
    _ = try orphan.encryptionKey()
    try orphan.paths().createDirectoriesIfNeeded()

    restorer.sweepOrphans(keeping: nil)

    #expect(FileManager.default.fileExists(atPath: try orphan.paths().storeDirectory.path))
}

@Test func anUnreadablePersistedSessionSweepsNothingWhenPreparing() throws {
    let root = newRoot()
    let restorer = makeRestorer(root: root)
    let orphan = LocalStore(
        storage: .local(directory: root),
        segment: .session("orphan"),
        secureStore: restorer.secureStore
    )
    _ = try orphan.encryptionKey()
    try orphan.paths().createDirectoriesIfNeeded()
    // Charge utile illisible : on ne sait pas quel store la session désigne.
    try restorer.secureStore.set(Data("illisible".utf8), forKey: SessionPersistence.storageKey)

    let store = try LoginAttemptStore.prepare(restorer: restorer, reusing: nil)

    #expect(FileManager.default.fileExists(atPath: try orphan.paths().storeDirectory.path))
    withExtendedLifetime(store) {}
}
