import Testing
import Foundation
import Security
@testable import MatrixClientKitRust
import MatrixClientKitCore

/// Une extension de notification s'exécute appareil verrouillé : avec `whenUnlocked`, elle ne
/// peut pas lire le jeton et la notification arrive vide. Ce test fige la constante Keychain
/// réellement utilisée pour l'accessibilité par défaut, afin qu'un renversement silencieux du
/// mapping (`afterFirstUnlock` → mauvaise constante) échoue bruyamment plutôt que de rester
/// invisible jusqu'à ce qu'une extension échoue en production.
@Test func afterFirstUnlockDefaultMapsToTheAfterFirstUnlockKeychainConstant() {
    let storage = MatrixStorage.local(directory: URL(fileURLWithPath: "/tmp/matrixclientkit-tests"))
    let store = KeychainSecureStore(storage: storage)

    #expect((store.secAccessibility as String) == (kSecAttrAccessibleAfterFirstUnlock as String))
}

@Test func whenUnlockedMapsToTheWhenUnlockedKeychainConstant() {
    let storage = MatrixStorage.local(
        directory: URL(fileURLWithPath: "/tmp/matrixclientkit-tests"),
        accessibility: .whenUnlocked
    )
    let store = KeychainSecureStore(storage: storage)

    #expect((store.secAccessibility as String) == (kSecAttrAccessibleWhenUnlocked as String))
}
