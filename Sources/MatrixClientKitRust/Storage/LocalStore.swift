import Foundation
import Security
import MatrixClientKitCore

/// Tout ce que le package écrit localement pour un utilisateur : les répertoires du store SQLite
/// et la clé qui le chiffre.
///
/// Regrouper les deux au même endroit n'est pas cosmétique : la clé et le store ne sont
/// utilisables que l'un avec l'autre, et les effacer dans le mauvais ordre rendrait le compte
/// inaccessible (voir ``purge()``).
struct LocalStore: Sendable {
    /// Préfixe de l'entrée Keychain portant la clé de chiffrement du store.
    ///
    /// Distinct de ``SessionPersistence/storageKey`` : la session et la clé ont des durées de vie
    /// et des conséquences de perte différentes, et une entrée qui en écraserait une autre
    /// déconnecterait l'utilisateur sans explication.
    static let keyPrefix = "com.matrixclientkit.store-key"

    /// Longueur exigée par `SqliteStoreBuilder.key(key:)` pour une clé brute.
    static let keyByteCount = 32

    let userID: UserID
    private let storage: MatrixStorage
    private let secureStore: any SecureStore

    init(storage: MatrixStorage, userID: UserID, secureStore: any SecureStore) {
        self.storage = storage
        self.userID = userID
        self.secureStore = secureStore
    }

    func paths() throws -> StoragePaths {
        try StoragePaths(storage: storage, userID: userID)
    }

    private var keychainKey: String {
        "\(Self.keyPrefix).\(StoragePaths.segment(for: userID))"
    }

    /// Relit la clé de chiffrement du store, ou en génère une à la première utilisation.
    ///
    /// - Important: la clé vit dans le Keychain et non à côté du store, pour deux raisons. D'une
    ///   part, une clé posée à côté de ce qu'elle chiffre ne chiffre rien : le conteneur partagé
    ///   d'un app group est un répertoire ordinaire, lisible par toute extension du groupe et
    ///   inclus dans les sauvegardes. D'autre part, le Keychain est le seul stockage dont
    ///   l'accessibilité peut être bornée à `afterFirstUnlock` — la même que la session, et pour
    ///   la même raison : une extension de notification doit pouvoir ouvrir le store appareil
    ///   verrouillé, sans quoi la notification arrive vide.
    ///
    /// - Important: ce qui dort dans ce store n'est pas seulement l'historique des messages, mais
    ///   le store crypto : identité d'appareil et clés de room Megolm.
    ///
    /// - Parameter createIfMissing: `false` dans l'extension de notification. Une clé absente y
    ///   signifie que l'application est en train de déconnecter la session : l'extension ne doit
    ///   ni recréer une clé ni purger un store qu'elle croirait orphelin, sans quoi un push reçu
    ///   pendant la déconnexion ferait réapparaître ce que l'application vient d'effacer. Elle
    ///   lève alors `MatrixError.authentication(.missingToken)` sans toucher au disque.
    func encryptionKey(createIfMissing: Bool = true) throws -> Data {
        if let existing = try secureStore.data(forKey: keychainKey) {
            // Une clé de mauvaise taille ne peut pas être remplacée en silence : la remplacer
            // rendrait définitivement illisible le store qu'elle chiffre. On signale la
            // corruption plutôt que de détruire les données.
            guard existing.count == Self.keyByteCount else {
                throw MatrixError.storage(.corrupted)
            }
            return existing
        }

        guard createIfMissing else {
            throw MatrixError.authentication(.missingToken)
        }

        // Clé absente alors qu'un store existe : celui-ci est déjà définitivement illisible, sa
        // clé n'existant plus nulle part. Le cas se produit quand l'entrée Keychain est perdue
        // sans que le conteneur le soit — un changement de `keychainAccessGroup` entre deux
        // versions de l'application, par exemple.
        //
        // Générer une clé neuve par-dessus laisserait l'application en échec à chaque lancement,
        // sans aucune API publique pour en sortir. On efface donc l'orphelin avant de repartir :
        // rien d'exploitable n'est perdu, puisque rien ne pouvait plus être déchiffré.
        try purgeOrphanedStore()

        let key = try Self.makeRandomKey()
        try secureStore.set(key, forKey: keychainKey)
        return key
    }

    /// Efface les répertoires d'un store dont la clé a disparu.
    private func purgeOrphanedStore() throws {
        let paths = try paths()
        guard FileManager.default.fileExists(atPath: paths.userDirectory.path) else { return }

        try remove(paths.dataDirectory)
        try remove(paths.cacheDirectory)
        try? remove(paths.userDirectory)
    }

    /// Efface le store local de cet utilisateur : répertoires d'abord, clé ensuite.
    ///
    /// - Important: l'ordre est la partie qui compte. Effacer la clé en premier puis échouer à
    ///   supprimer les répertoires laisserait sur disque un store chiffré dont plus personne ne
    ///   possède la clé — l'utilisateur ne pourrait plus jamais se reconnecter avec ce compte sur
    ///   cet appareil. Dans l'ordre inverse, un échec laisse au pire une clé orpheline, inoffensive.
    func purge() throws {
        let paths = try paths()
        try remove(paths.dataDirectory)
        try remove(paths.cacheDirectory)
        try? remove(paths.userDirectory)
        try secureStore.removeValue(forKey: keychainKey)
    }

    private func remove(_ directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }

    private static func makeRandomKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: keyByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
        return Data(bytes)
    }
}
