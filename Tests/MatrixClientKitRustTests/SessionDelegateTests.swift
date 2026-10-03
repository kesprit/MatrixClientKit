import Testing
import Foundation
import MatrixRustSDK
import MatrixClientKitCore
@testable import MatrixClientKitRust

private func makeSession(
    userId: String = "@alice:matrix.org",
    accessToken: String = "jeton-initial",
    refreshToken: String? = nil
) -> Session {
    Session(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: userId,
        deviceId: "DEV1",
        homeserverUrl: "https://matrix.org",
        oauthData: nil,
        slidingSyncVersion: .native
    )
}

private func persistedAlice(storeID: String? = "store-1") -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!, deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!, accessToken: "old", refreshToken: "r",
        oauthData: nil, slidingSyncVersion: "native", storeID: storeID
    )
}

@Test func aRefreshedSessionIsPersisted() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try persistence.save(persistedAlice())
    let delegate = SessionDelegate(persistence: persistence)

    // Ce que fait le SDK après avoir rafraîchi un jeton : sans cette écriture, la session
    // enregistrée se périme en silence et l'utilisateur se retrouve déconnecté au lancement suivant.
    delegate.saveSessionInKeychain(
        session: makeSession(accessToken: "jeton-rafraîchi", refreshToken: "refresh-rafraîchi")
    )

    let persisted = try persistence.load()
    #expect(persisted?.accessToken == "jeton-rafraîchi")
    #expect(persisted?.refreshToken == "refresh-rafraîchi")
}

@Test func thePersistedSessionIsHandedBackToTheSDK() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try persistence.save(persistedAlice())
    let delegate = SessionDelegate(persistence: persistence)
    delegate.saveSessionInKeychain(session: makeSession())

    let restored = try delegate.retrieveSessionFromKeychain(userId: "@alice:matrix.org")

    #expect(restored.accessToken == "jeton-initial")
    #expect(restored.userId == "@alice:matrix.org")
    #expect(restored.deviceId == "DEV1")
}

@Test func aSessionBelongingToAnotherUserIsRefused() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try persistence.save(persistedAlice())
    let delegate = SessionDelegate(persistence: persistence)

    // Servir aveuglément la session qui traîne donnerait au SDK les jetons d'un autre compte.
    #expect(throws: MatrixError.self) {
        try delegate.retrieveSessionFromKeychain(userId: "@bob:matrix.org")
    }
}

@Test func askingForASessionThatWasNeverPersistedThrows() throws {
    let delegate = SessionDelegate(persistence: SessionPersistence(store: InMemorySecureStore()))

    #expect(throws: MatrixError.self) {
        try delegate.retrieveSessionFromKeychain(userId: "@alice:matrix.org")
    }
}

@Test func aRefreshedSessionKeepsItsStoreID() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try persistence.save(
        MatrixSessionData(
            userID: UserID(rawValue: "@alice:matrix.org")!, deviceID: DeviceID(rawValue: "DEV1")!,
            homeserverURL: URL(string: "https://matrix.org")!, accessToken: "old", refreshToken: "r",
            oauthData: nil, slidingSyncVersion: "native", storeID: "store-1"
        ))
    let delegate = SessionDelegate(persistence: persistence)

    delegate.saveSessionInKeychain(
        session: Session(
            accessToken: "new", refreshToken: "r2", userId: "@alice:matrix.org", deviceId: "DEV1",
            homeserverUrl: "https://matrix.org", oauthData: nil, slidingSyncVersion: .native
        ))

    let saved = try #require(try persistence.load())
    #expect(saved.accessToken == "new")
    #expect(saved.storeID == "store-1")
}

@Test(arguments: [
    ("@alice:matrix.org", "DEV2"),  // même utilisateur, autre appareil
    ("@bob:matrix.org", "DEV1"),  // même appareil, autre utilisateur
    ("@bob:matrix.org", "DEV9"),  // une tout autre session
])
func anotherSessionsRefreshLeavesThePersistedEntryByteIdentical(userId: String, deviceId: String) throws {
    let secureStore = InMemorySecureStore()
    let persistence = SessionPersistence(store: secureStore)
    try persistence.save(persistedAlice())
    let before = try secureStore.data(forKey: SessionPersistence.storageKey)
    let delegate = SessionDelegate(persistence: persistence)

    // Une autre session vivante (une connexion plus ancienne, non persistée) rafraîchit son
    // jeton : écrire ses jetons, sans storeID, ferait rouvrir au lancement suivant le chemin
    // legacy et balayer les deux vrais stores.
    delegate.saveSessionInKeychain(
        session: Session(
            accessToken: "new", refreshToken: nil, userId: userId, deviceId: deviceId,
            homeserverUrl: "https://matrix.org", oauthData: nil, slidingSyncVersion: .native
        ))

    #expect(try secureStore.data(forKey: SessionPersistence.storageKey) == before)
}

@Test func aRefreshWithNothingPersistedWritesNothing() throws {
    let secureStore = InMemorySecureStore()
    let delegate = SessionDelegate(persistence: SessionPersistence(store: secureStore))

    // Seul `LoginAttempt.succeed` persiste une session neuve, avec son storeID ; un
    // rafraîchissement qui le devance est perdu, l'enregistrement de `succeed` le contient.
    delegate.saveSessionInKeychain(session: makeSession(accessToken: "new"))

    #expect(try secureStore.data(forKey: SessionPersistence.storageKey) == nil)
}

@Test func anUnreadablePersistedSessionIsLeftUntouchedByARefresh() throws {
    let secureStore = InMemorySecureStore()
    let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
    try secureStore.set(garbage, forKey: SessionPersistence.storageKey)
    let delegate = SessionDelegate(persistence: SessionPersistence(store: secureStore))

    delegate.saveSessionInKeychain(
        session: Session(
            accessToken: "new", refreshToken: nil, userId: "@alice:matrix.org", deviceId: "DEV1",
            homeserverUrl: "https://matrix.org", oauthData: nil, slidingSyncVersion: .native
        )
    )

    // Une lecture en échec n'est pas « rien de persisté » : écrire une session sans storeID
    // ferait rouvrir le chemin legacy au lancement suivant.
    #expect(try secureStore.data(forKey: SessionPersistence.storageKey) == garbage)
}
