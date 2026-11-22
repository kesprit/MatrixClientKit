import Foundation
import MatrixClientKitCore
import Security
import Testing

@testable import MatrixClientKitRust

private let dataProtectionKey = kSecUseDataProtectionKeychain as String
private let secret = Data("jeton".utf8)

private func makeStore(_ keychain: FakeKeychain) -> KeychainSecureStore {
    let storage = MatrixStorage.appGroup("group.com.example", keychainAccessGroup: "TEAM.com.example")
    return KeychainSecureStore(storage: storage, keychain: keychain)
}

/// Sur macOS, une requête sans cette clé vise l'ancien trousseau de session : une extension de
/// notification, d'une autre identité de code, s'y voit refuser la lecture
/// (`CSSMERR_CSP_NO_USER_INTERACTION`). Les seules requêtes sans la clé sont celles de la
/// migration, qui visent volontairement l'ancien trousseau : une lecture ou une suppression.
@Test func everyQueryTargetsTheDataProtectionKeychainExceptTheLegacyMigrationOnes() throws {
    let keychain = FakeKeychain()
    let store = makeStore(keychain)

    try store.set(secret, forKey: "a")
    try store.set(Data("autre".utf8), forKey: "a")
    _ = try store.data(forKey: "a")
    try store.removeValue(forKey: "a")
    _ = try store.data(forKey: "a")

    let calls = keychain.calls
    #expect(Set(calls.map(\.operation)) == [.copy, .update, .add, .delete])
    for call in calls where call.operation == .add || call.operation == .update {
        #expect(call.query[dataProtectionKey] as? Bool == true)
    }
    for call in calls where !call.usesDataProtection {
        #expect(call.operation == .copy || call.operation == .delete)
    }
    let firstCopy = try #require(calls.first { $0.operation == .copy })
    #expect(calls.contains { $0.operation == .delete && $0.usesDataProtection })
    #expect(firstCopy.usesDataProtection)
}

#if os(macOS)
    @Test func migratesALegacyItemToTheDataProtectionKeychainByAddingOnly() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        let store = makeStore(keychain)

        let value = try store.data(forKey: "a")

        #expect(value == secret)
        #expect(keychain.dataProtectionValue(account: "a") == secret)
        #expect(keychain.legacyValue(account: "a") == nil)
        #expect(
            keychain.calls.map(\.label)
                == ["copy-dp", "copy-legacy", "add-dp", "copy-dp", "delete-legacy"]
        )
        let legacyRead = try #require(keychain.calls.dropFirst().first).query
        #expect(legacyRead[dataProtectionKey] == nil)
        #expect(legacyRead[kSecAttrAccessGroup as String] as? String == "TEAM.com.example")
    }

    @Test func migrationIsIdempotent() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        let store = makeStore(keychain)

        _ = try store.data(forKey: "a")
        let callsAfterFirstRead = keychain.calls.count
        let second = try store.data(forKey: "a")

        #expect(second == secret)
        #expect(keychain.calls.count == callsAfterFirstRead + 1)
    }

    @Test func anItemAbsentFromBothKeychainsReadsAsNil() throws {
        let keychain = FakeKeychain()
        let store = makeStore(keychain)

        #expect(try store.data(forKey: "a") == nil)
        #expect(keychain.calls.map(\.label) == ["copy-dp", "copy-legacy", "copy-dp"])
    }

    @Test func aFailedDataProtectionWriteKeepsTheLegacyCopyAndThrows() {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.fail(.add, dataProtection: true, with: errSecMissingEntitlement)
        let store = makeStore(keychain)

        #expect(throws: MatrixError.storage(.keychainFailure(status: errSecMissingEntitlement))) {
            try store.data(forKey: "a")
        }
        #expect(keychain.legacyValue(account: "a") == secret)
        #expect(keychain.dataProtectionValue(account: "a") == nil)
        #expect(!keychain.calls.contains { $0.operation == .delete })
    }

    @Test func aDivergentReadBackReturnsTheDataProtectionValueAndTheNextReadAgrees() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.corruptNextDataProtectionWrite()
        let store = makeStore(keychain)

        let first = try store.data(forKey: "a")
        let stored = try #require(keychain.dataProtectionValue(account: "a"))
        let callsAfterFirstRead = keychain.calls.count
        let second = try store.data(forKey: "a")

        #expect(first == stored)
        #expect(second == stored)
        #expect(keychain.calls.count == callsAfterFirstRead + 1)
    }

    @Test func aLegacyReadFailureSurfacesAndWritesNothing() {
        let keychain = FakeKeychain()
        keychain.fail(.copy, dataProtection: false, with: errSecInteractionNotAllowed)
        let store = makeStore(keychain)

        #expect(throws: MatrixError.storage(.keychainFailure(status: errSecInteractionNotAllowed))) {
            try store.data(forKey: "a")
        }
        #expect(!keychain.calls.contains { $0.operation == .add || $0.operation == .update })
    }

    /// Lecteur L1 : rien en data protection. Avant sa lecture legacy, L2 migre et supprime le
    /// legacy. Renvoyer `nil` ferait balayer une session valide (et purger le store local).
    @Test func anEmptyLegacyReadRereadsTheDataProtectionKeychainBeforeReturningNil() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.beforeNext({ $0.label == "copy-legacy" }) {
            keychain.seedDataProtection(secret, account: "a")
            keychain.removeLegacy(account: "a")
        }
        let store = makeStore(keychain)

        #expect(try store.data(forKey: "a") == secret)
    }

    /// L1 lit la valeur legacy T0 ; un autre acteur migre puis enregistre T1 (jeton tourné).
    /// La migration n'écrit qu'en ajout : T1 ne doit jamais être écrasé par T0.
    @Test func aConcurrentMigrationAndRefreshIsNeverOverwrittenByTheStaleLegacyValue() throws {
        let newer = Data("jeton-tourné".utf8)
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.beforeNext({ $0.label == "add-dp" }) {
            keychain.seedDataProtection(newer, account: "a")
            keychain.removeLegacy(account: "a")
        }
        let store = makeStore(keychain)

        #expect(try store.data(forKey: "a") == newer)
        #expect(keychain.dataProtectionValue(account: "a") == newer)
        #expect(!keychain.calls.contains { $0.operation == .update })
    }

    @Test func aFailedLegacyDeletionStillReturnsTheValueAndRemovalCleansBothCopies() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.fail(.delete, dataProtection: false, with: errSecInteractionNotAllowed)
        let store = makeStore(keychain)

        #expect(try store.data(forKey: "a") == secret)
        #expect(keychain.dataProtectionValue(account: "a") == secret)
        #expect(keychain.legacyValue(account: "a") == secret)

        keychain.clearFailures()
        try store.removeValue(forKey: "a")

        #expect(keychain.legacyValue(account: "a") == nil)
        #expect(keychain.dataProtectionValue(account: "a") == nil)
    }

    @Test func removeValueDeletesTheLegacyCopyBeforeTheDataProtectionOne() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.seedDataProtection(secret, account: "a")
        let store = makeStore(keychain)

        try store.removeValue(forKey: "a")

        #expect(keychain.calls.map(\.label) == ["delete-legacy", "delete-dp"])
        #expect(keychain.legacyValue(account: "a") == nil)
        #expect(keychain.dataProtectionValue(account: "a") == nil)
    }

    /// Si la suppression legacy échoue, la copie data protection doit rester : sinon la lecture
    /// suivante « migrerait » une session révoquée depuis le legacy.
    @Test func aFailedLegacyRemovalLeavesNoResurrectableCopy() throws {
        let keychain = FakeKeychain()
        keychain.seedLegacy(secret, account: "a")
        keychain.seedDataProtection(secret, account: "a")
        keychain.fail(.delete, dataProtection: false, with: errSecInteractionNotAllowed)
        let store = makeStore(keychain)

        #expect(throws: MatrixError.storage(.keychainFailure(status: errSecInteractionNotAllowed))) {
            try store.removeValue(forKey: "a")
        }
        #expect(keychain.dataProtectionValue(account: "a") == secret)
        #expect(try store.data(forKey: "a") == secret)
        #expect(!keychain.calls.contains { $0.label == "add-dp" })
    }
#endif
