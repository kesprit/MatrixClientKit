import Foundation
import MatrixClientKitCore

/// Résout les répertoires utilisés par le store SQLite du SDK.
struct StoragePaths: Sendable {
    let dataDirectory: URL
    let cacheDirectory: URL

    init(storage: MatrixStorage) throws {
        let root: URL
        switch storage.location {
        case let .appGroup(identifier):
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw MatrixError.storage(.unavailable)
            }
            root = container
        case let .local(directory):
            root = directory
        }

        dataDirectory = root.appendingPathComponent("MatrixClientKit/data", isDirectory: true)
        cacheDirectory = root.appendingPathComponent("MatrixClientKit/cache", isDirectory: true)
    }

    /// Crée les répertoires et applique la protection de fichiers requise par les extensions.
    ///
    /// - Important: sans `completeUntilFirstUserAuthentication`, une extension de notification
    ///   plante à l'ouverture du store lorsque l'appareil est verrouillé.
    func createDirectoriesIfNeeded() throws {
        for directory in [dataDirectory, cacheDirectory] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
    }
}
