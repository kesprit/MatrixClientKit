import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private let alice = UserID(rawValue: "@alice:matrix.org")!
private let bob = UserID(rawValue: "@bob:matrix.org")!

private func makeRoot() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-\(UUID().uuidString)", isDirectory: true)
}

private func makeStore(
    root: URL,
    userID: UserID = alice,
    secureStore: any SecureStore = InMemorySecureStore()
) -> LocalStore {
    LocalStore(storage: .local(directory: root), userID: userID, secureStore: secureStore)
}

@Test func theEncryptionKeyIsGeneratedOnceAndSurvivesRelaunch() throws {
    let root = makeRoot()
    let secureStore = InMemorySecureStore()

    let first = try makeStore(root: root, secureStore: secureStore).encryptionKey()
    #expect(first.count == LocalStore.keyByteCount)

    // Une instance neuve représente un relancement de l'application : la clé doit être relue,
    // pas régénérée, sans quoi le store existant devient illisible.
    let second = try makeStore(root: root, secureStore: secureStore).encryptionKey()
    #expect(first == second)
}

@Test func eachUserGetsItsOwnEncryptionKey() throws {
    let root = makeRoot()
    let secureStore = InMemorySecureStore()

    let aliceKey = try makeStore(root: root, userID: alice, secureStore: secureStore).encryptionKey()
    let bobKey = try makeStore(root: root, userID: bob, secureStore: secureStore).encryptionKey()

    #expect(aliceKey != bobKey)
}

@Test func theEncryptionKeyIsStoredApartFromTheSession() throws {
    let secureStore = InMemorySecureStore()
    _ = try makeStore(root: makeRoot(), secureStore: secureStore).encryptionKey()

    #expect(try secureStore.data(forKey: SessionPersistence.storageKey) == nil)
}

@Test func aKeyOfTheWrongSizeIsReportedRatherThanReplaced() throws {
    let secureStore = InMemorySecureStore()
    let store = makeStore(root: makeRoot(), secureStore: secureStore)
    // Écrit sous la même entrée que celle qu'utilise `LocalStore`, en passant par une première
    // génération pour ne pas dupliquer le format de la clé Keychain dans le test.
    let key = try store.encryptionKey()
    let entry = try #require(
        try secureStore.data(forKey: "\(LocalStore.keyPrefix).\(StoragePaths.segment(for: alice))")
    )
    #expect(entry == key)

    try secureStore.set(Data([0x01, 0x02]), forKey: "\(LocalStore.keyPrefix).\(StoragePaths.segment(for: alice))")
    #expect(throws: MatrixError.storage(.corrupted)) {
        _ = try store.encryptionKey()
    }
}

@Test func purgeRemovesBothTheDirectoriesAndTheKey() throws {
    let root = makeRoot()
    let secureStore = InMemorySecureStore()
    let store = makeStore(root: root, secureStore: secureStore)

    let paths = try store.paths()
    try paths.createDirectoriesIfNeeded()
    _ = try store.encryptionKey()

    try store.purge()

    #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.path) == false)
    #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path) == false)
    #expect(FileManager.default.fileExists(atPath: paths.userDirectory.path) == false)
    #expect(try secureStore.data(forKey: "\(LocalStore.keyPrefix).\(StoragePaths.segment(for: alice))") == nil)

    try? FileManager.default.removeItem(at: root)
}

@Test func purgingAnAbsentStoreIsNotAnError() throws {
    let store = makeStore(root: makeRoot())
    try store.purge()
}

@Test func aStoreWhoseKeyDisappearedIsPurgedRatherThanLeftUnreadable() throws {
    let root = makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let secureStore = InMemorySecureStore()
    let store = makeStore(root: root, secureStore: secureStore)

    // Un store existant, avec un fichier dedans pour vérifier qu'il disparaît réellement.
    let key = try store.encryptionKey()
    let paths = try store.paths()
    try paths.createDirectoriesIfNeeded()
    let database = paths.dataDirectory.appendingPathComponent("matrix.sqlite")
    try Data("données chiffrées".utf8).write(to: database)

    // La clé disparaît sans que le store parte avec elle — cas d'un changement d'access group
    // du Keychain entre deux versions de l'application.
    try secureStore.removeValue(forKey: "\(LocalStore.keyPrefix).\(StoragePaths.segment(for: alice))")

    let regenerated = try makeStore(root: root, secureStore: secureStore).encryptionKey()

    #expect(regenerated.count == LocalStore.keyByteCount)
    #expect(regenerated != key)
    // L'orphelin doit être parti : le conserver condamnerait l'application à échouer à chaque
    // lancement, sans aucune API publique pour s'en sortir.
    #expect(FileManager.default.fileExists(atPath: database.path) == false)
    #expect(FileManager.default.fileExists(atPath: paths.userDirectory.path) == false)
}
