import Testing
import Foundation
@testable import MatrixClientKitCore

private func makeSessionData(token: String = "token") -> MatrixSessionData {
    MatrixSessionData(
        userID: UserID(rawValue: "@alice:matrix.org")!,
        deviceID: DeviceID(rawValue: "DEV1")!,
        homeserverURL: URL(string: "https://matrix.org")!,
        accessToken: token,
        refreshToken: nil,
        oauthData: nil,
        slidingSyncVersion: "native"
    )
}

@Test func loadReturnsNilWhenNothingWasSaved() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    #expect(try await persistence.load() == nil)
}

@Test func savedSessionIsLoadedBack() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    let session = makeSessionData()
    try await persistence.save(session)
    #expect(try await persistence.load() == session)
}

@Test func savingTwiceKeepsTheMostRecentSession() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try await persistence.save(makeSessionData(token: "ancien"))
    try await persistence.save(makeSessionData(token: "nouveau"))
    #expect(try await persistence.load()?.accessToken == "nouveau")
}

@Test func clearRemovesThePersistedSession() async throws {
    let persistence = SessionPersistence(store: InMemorySecureStore())
    try await persistence.save(makeSessionData())
    try await persistence.clear()
    #expect(try await persistence.load() == nil)
}

@Test func corruptedPayloadSurfacesAsStorageError() async throws {
    let store = InMemorySecureStore()
    try store.set(Data("pas du json".utf8), forKey: SessionPersistence.storageKey)
    let persistence = SessionPersistence(store: store)

    await #expect(throws: MatrixError.storage(.corrupted)) {
        _ = try await persistence.load()
    }
}
