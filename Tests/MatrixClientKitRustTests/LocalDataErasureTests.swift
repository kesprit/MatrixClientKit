import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private let alice = UserID(rawValue: "@alice:matrix.org")!
private let bob = UserID(rawValue: "@bob:matrix.org")!
private let dev1 = DeviceID(rawValue: "DEV1")!
private let dev2 = DeviceID(rawValue: "DEV2")!

private func persisted(_ userID: UserID, _ deviceID: DeviceID, storeID: String) -> MatrixSessionData {
    MatrixSessionData(
        userID: userID, deviceID: deviceID, homeserverURL: URL(string: "https://matrix.org")!,
        accessToken: "a", refreshToken: nil, oauthData: nil, slidingSyncVersion: "native", storeID: storeID
    )
}

private func makeStore(_ secureStore: InMemorySecureStore) throws -> LocalStore {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-\(UUID().uuidString)", isDirectory: true)
    let store = LocalStore(storage: .local(directory: root), segment: .newSession(), secureStore: secureStore)
    _ = try store.encryptionKey()
    try store.paths().createDirectoriesIfNeeded()
    return store
}

private func storeExists(_ store: LocalStore) throws -> Bool {
    FileManager.default.fileExists(atPath: try store.paths().dataDirectory.path)
}

@Test func erasingTheLocalDataOfThePersistedSessionClearsItsEntry() throws {
    let secureStore = InMemorySecureStore()
    let persistence = SessionPersistence(store: secureStore)
    let store = try makeStore(secureStore)
    try persistence.save(persisted(alice, dev1, storeID: try #require(store.segment.storeID)))

    try RustMatrixSession.eraseLocalData(
        persistence: persistence, localStore: store, userID: alice, deviceID: dev1)

    #expect(try persistence.load() == nil)
    #expect(try !storeExists(store))
}

@Test(arguments: [(alice, dev2), (bob, dev1)])
func erasingAnOlderSessionKeepsTheNewerPersistedEntry(userID: UserID, deviceID: DeviceID) throws {
    let secureStore = InMemorySecureStore()
    let persistence = SessionPersistence(store: secureStore)
    let older = try makeStore(secureStore)
    let newer = persisted(alice, dev1, storeID: "store-of-the-newer-session")
    try persistence.save(newer)

    // La déconnexion d'une session plus ancienne, non persistée, ne doit pas effacer l'entrée de
    // la plus récente connexion : l'utilisateur serait déconnecté et son store balayé au
    // lancement suivant. Son propre store, lui, est effacé.
    try RustMatrixSession.eraseLocalData(
        persistence: persistence, localStore: older, userID: userID, deviceID: deviceID)

    #expect(try persistence.load() == newer)
    #expect(try !storeExists(older))
}

@Test func erasingWithNothingPersistedStillPurgesTheStore() throws {
    let secureStore = InMemorySecureStore()
    let store = try makeStore(secureStore)

    try RustMatrixSession.eraseLocalData(
        persistence: SessionPersistence(store: secureStore), localStore: store, userID: alice, deviceID: dev1)

    #expect(try !storeExists(store))
}
