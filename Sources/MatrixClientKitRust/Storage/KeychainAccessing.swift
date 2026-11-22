import Foundation
import Security

/// Couture sur `SecItem*` : `KeychainSecureStore` n'appelle jamais `SecItem*` directement, pour
/// qu'un test capture les dictionnaires de requête réellement émis.
///
/// Les méthodes renvoient le `OSStatus` brut : l'interprétation reste dans `KeychainSecureStore`,
/// que le test exerce.
package protocol KeychainAccessing: Sendable {
    func copyData(matching query: [String: Any]) -> (status: OSStatus, data: Data?)
    func update(matching query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(matching query: [String: Any]) -> OSStatus
}

package struct SystemKeychain: KeychainAccessing {
    package init() {}

    package func copyData(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    package func update(matching query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    package func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    package func delete(matching query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
