import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

private let alice = UserID(rawValue: "@alice:matrix.org")!
private let bob = UserID(rawValue: "@bob:matrix.org")!

@Test func localStorageUsesTheProvidedDirectory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), userID: alice)

    #expect(paths.dataDirectory.path.hasPrefix(root.path))
    #expect(paths.cacheDirectory.path.hasPrefix(root.path))
    #expect(paths.dataDirectory != paths.cacheDirectory)
}

@Test func directoriesAreCreatedOnDemand() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-\(UUID().uuidString)", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root), userID: alice)
    try paths.createDirectoriesIfNeeded()

    #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.path))
    #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))

    try? FileManager.default.removeItem(at: root)
}

@Test func missingAppGroupContainerSurfacesAsStorageError() {
    #expect(throws: MatrixError.storage(.unavailable)) {
        _ = try StoragePaths(
            storage: .appGroup("group.invalide.inexistant"),
            userID: alice,
            containerURL: { _ in nil }
        )
    }
}

@Test func eachUserGetsItsOwnStore() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let alicePaths = try StoragePaths(storage: .local(directory: root), userID: alice)
    let bobPaths = try StoragePaths(storage: .local(directory: root), userID: bob)

    #expect(alicePaths.dataDirectory != bobPaths.dataDirectory)
    #expect(alicePaths.cacheDirectory != bobPaths.cacheDirectory)
    #expect(alicePaths.userDirectory != bobPaths.userDirectory)
}

/// Épingle la valeur littérale du segment : un segment recalculé différemment d'un lancement à
/// l'autre (par exemple via `hashValue`, dont la graine est aléatoire par processus) rendrait le
/// store introuvable après un redémarrage, sans erreur — l'utilisateur verrait simplement un
/// compte vide.
@Test func theUserSegmentIsStableAcrossLaunches() {
    #expect(StoragePaths.segment(for: alice) == "a5829e99c7bc42227c63db8609d87392")
}
