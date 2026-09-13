import Testing
import Foundation
@testable import MatrixClientKitRust
import MatrixClientKitCore

@Test func localStorageUsesTheProvidedDirectory() throws {
    let root = URL(fileURLWithPath: "/tmp/matrixclientkit-tests", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root))

    #expect(paths.dataDirectory.path.hasPrefix(root.path))
    #expect(paths.cacheDirectory.path.hasPrefix(root.path))
    #expect(paths.dataDirectory != paths.cacheDirectory)
}

@Test func directoriesAreCreatedOnDemand() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mck-\(UUID().uuidString)", isDirectory: true)
    let paths = try StoragePaths(storage: .local(directory: root))
    try paths.createDirectoriesIfNeeded()

    #expect(FileManager.default.fileExists(atPath: paths.dataDirectory.path))
    #expect(FileManager.default.fileExists(atPath: paths.cacheDirectory.path))

    try? FileManager.default.removeItem(at: root)
}

@Test func missingAppGroupContainerSurfacesAsStorageError() {
    #expect(throws: MatrixError.storage(.unavailable)) {
        _ = try StoragePaths(storage: .appGroup("group.invalide.inexistant"), containerURL: { _ in nil })
    }
}
