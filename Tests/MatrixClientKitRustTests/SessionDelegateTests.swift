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

@Test func aRefreshedSessionIsPersisted() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
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
    let delegate = SessionDelegate(persistence: persistence)
    delegate.saveSessionInKeychain(session: makeSession())

    let restored = try delegate.retrieveSessionFromKeychain(userId: "@alice:matrix.org")

    #expect(restored.accessToken == "jeton-initial")
    #expect(restored.userId == "@alice:matrix.org")
    #expect(restored.deviceId == "DEV1")
}

@Test func aSessionBelongingToAnotherUserIsRefused() throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    let delegate = SessionDelegate(persistence: persistence)
    delegate.saveSessionInKeychain(session: makeSession(userId: "@alice:matrix.org"))

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
