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

    package init(storage: MatrixStorage) {
        accessGroup = storage.keychainAccessGroup
        accessibility = storage.accessibility
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

    private func baseQuery(forKey key: String) -> [String: Any] {
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

    package func data(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess: return result as? Data
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

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = secAccessibility
            let addStatus = SecItemAdd(insertion as CFDictionary, nil)

            // Un autre écrivain a créé l'entrée entre notre `SecItemUpdate` et notre `SecItemAdd`.
            // Le cas n'est pas théorique : l'application et son extension de notification
            // partagent le même access group et rafraîchissent la même session. Sans cette
            // reprise, la perdante des deux voit son écriture échouer alors que la valeur est
            // parfaitement écrivable — et c'est un jeton de session qu'elle perd.
            if addStatus == errSecDuplicateItem {
                let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
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
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
    }
}
