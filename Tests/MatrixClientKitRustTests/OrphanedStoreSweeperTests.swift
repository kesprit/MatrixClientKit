import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private struct Fixture {
    let root: URL
    let secureStore = InMemorySecureStore()
    let registry = StoreRegistry()

    init(
        root: URL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mck-\(UUID().uuidString)")
    ) {
        self.root = root
    }
    var storage: MatrixStorage { .local(directory: root) }

    /// Crée un store sur disque (répertoires + clé) et le rend.
    func makeStore(_ segment: StoreSegment) throws -> LocalStore {
        let store = LocalStore(storage: storage, segment: segment, secureStore: secureStore)
        _ = try store.encryptionKey()
        try store.paths().createDirectoriesIfNeeded()
        return store
    }

    func exists(_ store: LocalStore) throws -> Bool {
        FileManager.default.fileExists(atPath: try store.paths().storeDirectory.path)
    }

    func hasKey(_ segment: StoreSegment) throws -> Bool {
        try secureStore.data(forKey: "\(LocalStore.keyPrefix).\(segment.directoryName)") != nil
    }

    var sweeper: OrphanedStoreSweeper {
        OrphanedStoreSweeper(storage: storage, secureStore: secureStore, registry: registry)
    }
}

@Test func thePersistedSessionsStoreIsKept() throws {
    let fixture = Fixture()
    let kept = try fixture.makeStore(.session("kept-1"))
    fixture.sweeper.sweep(keeping: .session("kept-1"))
    #expect(try fixture.exists(kept))
    #expect(try fixture.hasKey(.session("kept-1")))
}

@Test func anUnleasedUnpersistedStoreIsRemovedWithItsKey() throws {
    let fixture = Fixture()
    let orphan = try fixture.makeStore(.session("orphan-1"))
    fixture.sweeper.sweep(keeping: .session("kept-1"))
    #expect(try !fixture.exists(orphan))
    #expect(try !fixture.hasKey(.session("orphan-1")))
}

@Test func anOrphanedLegacyStoreIsRemovedToo() throws {
    // Le cas 0.3 : une connexion par-dessus une session persistée laissait l'ancien store.
    let fixture = Fixture()
    let bob = UserID(rawValue: "@bob:matrix.org")!
    let orphan = try fixture.makeStore(.legacy(bob))
    fixture.sweeper.sweep(keeping: nil)
    #expect(try !fixture.exists(orphan))
    #expect(try !fixture.hasKey(.legacy(bob)))
}

// Review Focus 3 : un store ouvert par une session vivante du processus n'est jamais ramassé,
// même quand l'entrée Keychain désigne une autre session.
@Test func aLeasedStoreIsNeverRemoved() throws {
    let fixture = Fixture()
    let live = try fixture.makeStore(.session("live-1"))
    let lease = fixture.registry.lease(try live.paths())
    fixture.sweeper.sweep(keeping: .session("other"))
    #expect(try fixture.exists(live))
    withExtendedLifetime(lease) {}
}

@Test func releasingTheLeaseMakesTheStoreCollectable() throws {
    let fixture = Fixture()
    let live = try fixture.makeStore(.session("live-1"))
    let lease = fixture.registry.lease(try live.paths())
    lease.release()
    fixture.sweeper.sweep(keeping: nil)
    #expect(try !fixture.exists(live))
}

@Test func twoLeasesOnTheSameStoreNeedTwoReleases() throws {
    // Reconnexion : la session remplacée et sa remplaçante tiennent le même store.
    let fixture = Fixture()
    let store = try fixture.makeStore(.session("shared"))
    let first = fixture.registry.lease(try store.paths())
    let second = fixture.registry.lease(try store.paths())
    first.release()
    #expect(fixture.registry.isLeased(try store.paths().storeDirectory))
    second.release()
    #expect(!fixture.registry.isLeased(try store.paths().storeDirectory))
}

@Test func aMissingRootIsNotAnError() throws {
    let fixture = Fixture()
    fixture.sweeper.sweep(keeping: nil)  // ne lève pas, ne crée rien
    #expect(!FileManager.default.fileExists(atPath: try StoragePaths.root(for: fixture.storage).path))
}

@Test func filesBesideTheStoresAreLeftAlone() throws {
    let fixture = Fixture()
    let root = try StoragePaths.root(for: fixture.storage)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("note.txt")
    try Data("x".utf8).write(to: file)
    fixture.sweeper.sweep(keeping: nil)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

// Le bail est pris avant que le répertoire existe, le ramassage passe après : les deux doivent
// désigner le store par la même clé, quelle que soit la forme du chemin racine.
@Test func aLeaseTakenBeforeTheDirectoryExistsProtectsTheStoreUnderAPrivateRoot() throws {
    let fixture = Fixture(
        root: URL(fileURLWithPath: "/private" + NSTemporaryDirectory())
            .appendingPathComponent("mck-\(UUID().uuidString)")
    )
    let store = LocalStore(storage: fixture.storage, segment: .session("early"), secureStore: fixture.secureStore)
    let lease = fixture.registry.lease(try store.paths())
    _ = try fixture.makeStore(.session("early"))
    fixture.sweeper.sweep(keeping: nil)
    #expect(try fixture.exists(store))
    withExtendedLifetime(lease) {}
}

@Test func aLeaseTakenBeforeTheDirectoryExistsProtectsTheStoreUnderASymlinkedRoot() throws {
    let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-real-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let link = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-link-\(UUID().uuidString)")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let fixture = Fixture(root: link)
    let store = LocalStore(storage: fixture.storage, segment: .session("early"), secureStore: fixture.secureStore)
    let lease = fixture.registry.lease(try store.paths())
    _ = try fixture.makeStore(.session("early"))
    fixture.sweeper.sweep(keeping: nil)
    #expect(try fixture.exists(store))
    withExtendedLifetime(lease) {}
}

@Test func aForeignDirectoryWithoutStoreLayoutIsLeftAlone() throws {
    let fixture = Fixture()
    let foreign = try StoragePaths.root(for: fixture.storage).appendingPathComponent("foreign", isDirectory: true)
    try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
    fixture.sweeper.sweep(keeping: nil)
    #expect(FileManager.default.fileExists(atPath: foreign.path))
}
