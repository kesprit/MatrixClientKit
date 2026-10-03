import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private struct Fixture {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mck-\(UUID().uuidString)")
    let secureStore = InMemorySecureStore()
    let registry = StoreRegistry()
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

@Test func aMissingRootIsNotAnError() {
    Fixture().sweeper.sweep(keeping: nil)  // ne lève pas, ne crée rien
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
