import Foundation
import MatrixClientKitCore

/// Résout les répertoires utilisés par le store SQLite du SDK, pour un segment de store donné.
///
/// - Important: l'amont documente que les chemins « **must** be unique per session as the SDK
///   stores aren't capable of handling multiple users ». Un chemin fixe partagé par tous les
///   comptes fait donc rouvrir le store — et le store crypto — du compte précédent lors d'une
///   connexion sous un autre identifiant : configuration non supportée, qui échoue sans erreur
///   exploitable. D'où un segment par store : l'empreinte du user ID pour les sessions 0.1 à 0.3, un identifiant
///   aléatoire par session ensuite — voir ``StoreSegment``.
struct StoragePaths: Sendable {
    /// Répertoire propre au store : contient ``dataDirectory`` et ``cacheDirectory``.
    let storeDirectory: URL
    let dataDirectory: URL
    let cacheDirectory: URL

    /// - Parameters:
    ///   - storage: emplacement racine choisi par l'application.
    ///   - segment: store désigné. Pour une session legacy, le segment de chemin est dérivé du
    ///     user ID par empreinte : un identifiant Matrix brut (`@alice:matrix.org`) contient `@` et
    ///     `:`, et deux identifiants ne différant que par la casse se retrouveraient dans le même
    ///     répertoire sur un système de fichiers insensible à la casse.
    ///   - containerURL: résout l'URL du conteneur d'un app group. Injectable car ce
    ///     comportement diffère selon la plateforme : sur iOS, `FileManager` retourne `nil` pour un
    ///     app group absent des entitlements ; sur macOS non sandboxé (dont les tests SwiftPM), il
    ///     synthétise un chemin sous `~/Library/Group Containers/` quelle que soit l'entitlement.
    ///     L'injection permet de figer le chemin d'échec par le test plutôt que par le comportement
    ///     de l'hôte.
    init(
        storage: MatrixStorage,
        segment: StoreSegment,
        containerURL: (String) -> URL? = { identifier in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
    ) throws {
        storeDirectory = try Self.root(for: storage, containerURL: containerURL)
            .appendingPathComponent(segment.directoryName, isDirectory: true)
        dataDirectory = storeDirectory.appendingPathComponent("data", isDirectory: true)
        cacheDirectory = storeDirectory.appendingPathComponent("cache", isDirectory: true)
    }

    /// `<conteneur ou répertoire>/MatrixClientKit` : le parent de tous les stores d'un stockage.
    static func root(
        for storage: MatrixStorage,
        containerURL: (String) -> URL? = { identifier in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
    ) throws -> URL {
        let base: URL
        switch storage.location {
        case let .appGroup(identifier):
            guard let container = containerURL(identifier) else {
                throw MatrixError.storage(.unavailable)
            }
            base = container
        case let .local(directory):
            base = directory
        }
        return base.appendingPathComponent("MatrixClientKit", isDirectory: true)
    }

    /// Segment de chemin propre à un utilisateur, sûr pour le système de fichiers et stable d'un
    /// lancement à l'autre — voir ``StableDigest``.
    static func segment(for userID: UserID) -> String {
        StableDigest.short(userID.rawValue)
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
