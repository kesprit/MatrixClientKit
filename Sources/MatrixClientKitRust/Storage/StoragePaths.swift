import Foundation
import MatrixClientKitCore

/// Résout les répertoires utilisés par le store SQLite du SDK.
struct StoragePaths: Sendable {
    let dataDirectory: URL
    let cacheDirectory: URL

    /// - Parameter containerURL: résout l'URL du conteneur d'un app group. Injectable car ce
    ///   comportement diffère selon la plateforme : sur iOS, `FileManager` retourne `nil` pour un
    ///   app group absent des entitlements ; sur macOS non sandboxé (dont les tests SwiftPM), il
    ///   synthétise un chemin sous `~/Library/Group Containers/` quelle que soit l'entitlement.
    ///   L'injection permet de figer le chemin d'échec par le test plutôt que par le comportement
    ///   de l'hôte.
    init(
        storage: MatrixStorage,
        containerURL: (String) -> URL? = { identifier in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
    ) throws {
        let root: URL
        switch storage.location {
        case let .appGroup(identifier):
            guard let container = containerURL(identifier) else {
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
