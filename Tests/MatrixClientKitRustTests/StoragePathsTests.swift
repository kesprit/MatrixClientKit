import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private let alice = UserID(rawValue: "@alice:matrix.org")!
private let bob = UserID(rawValue: "@bob:matrix.org")!

@Test func localStorageUsesTheProvidedDirectory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), segment: .legacy(alice))

    #expect(paths.dataDirectory.path.hasPrefix(root.path))
    #expect(paths.cacheDirectory.path.hasPrefix(root.path))
    #expect(paths.dataDirectory != paths.cacheDirectory)
}

@Test func directoriesAreCreatedOnDemand() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-\(UUID().uuidString)", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), segment: .legacy(alice))
    try paths.createDirectoriesIfNeeded()

    #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.path))
    #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))

    try? FileManager.default.removeItem(at: root)
}

@Test func missingAppGroupContainerSurfacesAsStorageError() {
    #expect(throws: MatrixError.storage(.unavailable)) {
        _ = try StoragePaths(
            storage: .appGroup("group.invalide.inexistant"),
            segment: .legacy(alice),
            containerURL: { _ in nil }
        )
    }
}

@Test func eachUserGetsItsOwnStore() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let alicePaths = try StoragePaths(storage: .local(directory: root), segment: .legacy(alice))
    let bobPaths = try StoragePaths(storage: .local(directory: root), segment: .legacy(bob))

    #expect(alicePaths.dataDirectory != bobPaths.dataDirectory)
    #expect(alicePaths.cacheDirectory != bobPaths.cacheDirectory)
    #expect(alicePaths.storeDirectory != bobPaths.storeDirectory)
}

/// Épingle la valeur littérale du segment : un segment recalculé différemment d'un lancement à
/// l'autre (par exemple via `hashValue`, dont la graine est aléatoire par processus) rendrait le
/// store introuvable après un redémarrage, sans erreur — l'utilisateur verrait simplement un
/// compte vide.
@Test func theUserSegmentIsStableAcrossLaunches() {
    #expect(StoragePaths.segment(for: alice) == "a5829e99c7bc42227c63db8609d87392")
}

@Test func aSessionSegmentUsesItsStoreIDAsDirectory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), segment: .session("0b1c-uuid"))
    #expect(paths.storeDirectory.lastPathComponent == "0b1c-uuid")
    #expect(paths.storeDirectory.deletingLastPathComponent().lastPathComponent == "MatrixClientKit")
}

@Test func theLegacySegmentKeepsThe03Directory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), segment: .legacy(alice))
    // Valeur épinglée par `theUserSegmentIsStableAcrossLaunches` : une session 0.3 doit
    // retrouver son store exactement là où la 0.3 l'a créé.
    #expect(paths.storeDirectory.lastPathComponent == "a5829e99c7bc42227c63db8609d87392")
    #expect(
        paths.storeDirectory.path
            == root.appendingPathComponent("MatrixClientKit/a5829e99c7bc42227c63db8609d87392").path
    )
}

@Test func newSessionSegmentsAreDistinctAndNeverLookLikeADigest() {
    let a = StoreSegment.newSession().directoryName
    let b = StoreSegment.newSession().directoryName
    #expect(a != b)
    #expect(a.contains("-"))  // un UUID ; une empreinte StableDigest n'a jamais de tiret
}

@Test func theSegmentFollowsThePersistedData() {
    let legacy = MatrixSessionData(
        userID: alice, deviceID: DeviceID(rawValue: "D")!, homeserverURL: URL(string: "https://m.org")!,
        accessToken: "t", refreshToken: nil, oauthData: nil, slidingSyncVersion: "native"
    )
    #expect(StoreSegment(legacy) == .legacy(alice))
    let modern = MatrixSessionData(
        userID: alice, deviceID: DeviceID(rawValue: "D")!, homeserverURL: URL(string: "https://m.org")!,
        accessToken: "t", refreshToken: nil, oauthData: nil, slidingSyncVersion: "native", storeID: "abc-1"
    )
    #expect(StoreSegment(modern) == .session("abc-1"))
}
