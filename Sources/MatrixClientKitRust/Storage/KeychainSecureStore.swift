import Foundation
import Security
import MatrixClientKitCore

/// Stockage de secrets adossé au Keychain, partageable avec une extension via un access group.
public struct KeychainSecureStore: SecureStore {
    private let service = "com.matrixclientkit"
    private let accessGroup: String?
    // Stocké sous forme de valeur Sendable : `CFString` (retourné par les constantes
    // `kSecAttrAccessible*`) ne conforme pas à `Sendable`, donc la résolution en `CFString`
    // est différée à l'utilisation dans `set`.
    private let accessibility: MatrixStorage.KeychainAccessibility

    public init(storage: MatrixStorage) {
        accessGroup = storage.keychainAccessGroup
        accessibility = storage.accessibility
    }

    private var secAccessibility: CFString {
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

    public func data(forKey key: String) throws -> Data? {
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

    public func set(_ data: Data, forKey key: String) throws {
        try removeValue(forKey: key)

        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = secAccessibility

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
    }

    public func removeValue(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MatrixError.storage(.keychainFailure(status: status))
        }
    }
}
