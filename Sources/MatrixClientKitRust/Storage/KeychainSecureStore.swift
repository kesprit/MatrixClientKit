import Foundation
import Security
import MatrixClientKitCore

/// Stockage de secrets adossé au Keychain, partageable avec une extension via un access group.
///
/// - Note: portée `package`, comme ``SecureStore`` : construit en interne par le client, jamais
///   injecté par une application.
package struct KeychainSecureStore: SecureStore {
    private let service = "com.matrixclientkit"
    private let accessGroup: String?
    // Stocké sous forme de valeur Sendable : `CFString` (retourné par les constantes
    // `kSecAttrAccessible*`) ne conforme pas à `Sendable`, donc la résolution en `CFString`
    // est différée à l'utilisation dans `set`.
    private let accessibility: MatrixStorage.KeychainAccessibility
    private let keychain: any KeychainAccessing

    package init(storage: MatrixStorage, keychain: any KeychainAccessing = SystemKeychain()) {
        accessGroup = storage.keychainAccessGroup
        accessibility = storage.accessibility
        self.keychain = keychain
    }

    // Visibilité interne (et non `private`) pour rester vérifiable par un test : un
    // renversement silencieux de ce mapping (`afterFirstUnlock` → mauvaise constante)
    // resterait invisible jusqu'à ce qu'une extension échoue à lire le jeton, appareil verrouillé.
    var secAccessibility: CFString {
        switch accessibility {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
        }
    }

    /// Requête de base, toujours adressée au trousseau data protection.
    ///
    /// Sur macOS, sans `kSecUseDataProtectionKeychain`, l'élément va dans l'ancien trousseau de
    /// session (file-based) : une extension de notification, d'une autre identité de code mais du
    /// même access group, s'y voit refuser la lecture (`CSSMERR_CSP_NO_USER_INTERACTION`, constaté
    /// sur macOS 27.2). Sur iOS la clé est sans effet. Seule `legacyQuery(forKey:)` l'omet.
    private func baseQuery(forKey key: String) -> [String: Any] {
        var query = legacyQuery(forKey: key)
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    private func legacyQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    /// Lit dans le trousseau data protection ; sur macOS, un élément absent est cherché dans
    /// l'ancien trousseau et migré.
    package func data(forKey key: String) throws -> Data? {
        if let value = try readData(query: baseQuery(forKey: key)) {
            return value
        }
        #if os(macOS)
            return try migrateLegacyItem(forKey: key)
        #else
            return nil
        #endif
    }

    #if os(macOS)
        /// Migration paresseuse, déclenchée par la première lecture qui ne trouve rien dans le
        /// trousseau data protection (décision du 2026-11-22). Une migration au démarrage ou à
        /// l'ouverture du client aurait dû être appelée par chaque cible. Seule l'application
        /// peut migrer : l'extension de notification, d'une autre identité de code, n'a pas le
        /// droit de lire l'ancien trousseau (c'est le défaut corrigé ici), sa lecture de
        /// l'ancien élément lève donc une erreur de stockage tant que l'application n'a pas lu
        /// la session une fois après la mise à jour.
        ///
        /// La migration n'écrit qu'en ajout, jamais en mise à jour : l'ancienne valeur lue peut
        /// être périmée si un autre lecteur (deuxième `restore`, deuxième instance) a migré puis
        /// rafraîchi la session entre-temps, et un `set` écraserait le jeton rafraîchi. Sur
        /// `errSecDuplicateItem`, la valeur data protection fait foi et est renvoyée. De même,
        /// un ancien élément vide ne vaut « pas de session » qu'après une relecture data
        /// protection : un autre lecteur a pu le migrer et le supprimer entre nos deux lectures,
        /// et renvoyer `nil` ferait balayer une session valide.
        ///
        /// Ordre : lire l'ancien élément (sans la clé), l'ajouter avec la clé, relire la copie
        /// data protection, et seulement alors supprimer l'ancien. Un échec avant l'ajout laisse
        /// l'ancien élément intact : la lecture lève et la suivante recommence. Une suppression
        /// de l'ancien élément qui échoue n'invalide pas la migration (la valeur est déjà en
        /// sécurité côté data protection, qui prime ensuite) ; `removeValue(forKey:)` supprime les
        /// deux copies à la déconnexion.
        private func migrateLegacyItem(forKey key: String) throws -> Data? {
            let dataProtectionQuery = baseQuery(forKey: key)
            guard let legacyData = try readData(query: legacyQuery(forKey: key)) else {
                return try readData(query: dataProtectionQuery)
            }

            var insertion = dataProtectionQuery
            insertion[kSecValueData as String] = legacyData
            insertion[kSecAttrAccessible as String] = secAccessibility
            let addStatus = keychain.add(insertion)
            guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
                throw MatrixError.storage(.keychainFailure(status: addStatus))
            }

            let stored = try readData(query: dataProtectionQuery)
            if stored != nil {
                _ = keychain.delete(matching: legacyQuery(forKey: key))
            }
            return stored
        }
    #endif

    private func readData(query base: [String: Any]) throws -> Data? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, data) = keychain.copyData(matching: query)

        switch status {
        case errSecSuccess: return data
        case errSecItemNotFound: return nil
        default: throw MatrixError.storage(.keychainFailure(status: status))
        }
    }

    /// Met à jour l'entrée existante plutôt que de la supprimer puis la recréer.
    ///
    /// - Important: un delete-puis-add laisse une fenêtre pendant laquelle aucune valeur n'existe.
    ///   Un échec du `SecItemAdd` dans cette fenêtre est indiscernable de « jamais connecté » :
    ///   `load()` renvoie alors `nil` au lieu de faire remonter l'échec, et l'utilisateur se
    ///   retrouve déconnecté sans explication — précisément ce que la décision de sécurité sur le
    ///   traitement des données corrompues doit empêcher.
    package func set(_ data: Data, forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: secAccessibility,
        ]

        let updateStatus = keychain.update(matching: query, attributes: attributes)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = secAccessibility
            let addStatus = keychain.add(insertion)

            // Un autre écrivain a créé l'entrée entre notre `SecItemUpdate` et notre `SecItemAdd`.
            // Le cas n'est pas théorique : l'application et son extension de notification
            // partagent le même access group et rafraîchissent la même session. Sans cette
            // reprise, la perdante des deux voit son écriture échouer alors que la valeur est
            // parfaitement écrivable — et c'est un jeton de session qu'elle perd.
            if addStatus == errSecDuplicateItem {
                let retryStatus = keychain.update(matching: query, attributes: attributes)
                guard retryStatus == errSecSuccess else {
                    throw MatrixError.storage(.keychainFailure(status: retryStatus))
                }
                return
            }

            guard addStatus == errSecSuccess else {
                throw MatrixError.storage(.keychainFailure(status: addStatus))
            }
        default:
            throw MatrixError.storage(.keychainFailure(status: updateStatus))
        }
    }

    package func removeValue(forKey key: String) throws {
        // L'ancienne copie d'abord : si sa suppression échoue, la copie data protection reste, et
        // la lecture suivante ne « migre » pas une session révoquée depuis l'ancien trousseau.
        #if os(macOS)
            try delete(query: legacyQuery(forKey: key))
        #endif
        try delete(query: baseQuery(forKey: key))
    }

    private func delete(query: [String: Any]) throws {
        let status = keychain.delete(matching: query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
    }
}
