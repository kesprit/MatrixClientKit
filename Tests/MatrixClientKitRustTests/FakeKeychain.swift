import Foundation
import Security

@testable import MatrixClientKitRust

/// Trousseau en mémoire qui sépare, comme macOS, l'ancien trousseau de session du trousseau
/// data protection : une requête appartient à ce dernier si elle porte
/// `kSecUseDataProtectionKeychain: true`. Il enregistre chaque requête reçue.
final class FakeKeychain: KeychainAccessing, @unchecked Sendable {
    enum Operation: Equatable { case copy, update, add, delete }

    struct Call {
        let operation: Operation
        let query: [String: Any]

        var usesDataProtection: Bool { query[kSecUseDataProtectionKeychain as String] as? Bool == true }
        var account: String? { query[kSecAttrAccount as String] as? String }
        var label: String { "\(operation)-\(usesDataProtection ? "dp" : "legacy")" }
    }

    private struct Failure {
        let operation: Operation
        let dataProtection: Bool
        let status: OSStatus
    }

    private struct Interception {
        let matches: (Call) -> Bool
        let action: () -> Void
    }

    private let lock = NSLock()
    private var interceptions: [Interception] = []
    private var legacy: [String: Data] = [:]
    private var dataProtection: [String: Data] = [:]
    private var recorded: [Call] = []
    private var failures: [Failure] = []
    private var corruptsNextDataProtectionWrite = false

    var calls: [Call] { lock.withLock { recorded } }

    func seedLegacy(_ data: Data, account: String) { lock.withLock { legacy[account] = data } }
    func seedDataProtection(_ data: Data, account: String) { lock.withLock { dataProtection[account] = data } }
    func legacyValue(account: String) -> Data? { lock.withLock { legacy[account] } }
    func dataProtectionValue(account: String) -> Data? { lock.withLock { dataProtection[account] } }

    func removeLegacy(account: String) { lock.withLock { legacy[account] = nil } }
    func clearFailures() { lock.withLock { failures = [] } }

    /// Exécute `action` une seule fois, juste avant le premier appel qui satisfait `matches`,
    /// hors du verrou : simule un autre acteur qui agit entre deux appels du store testé.
    func beforeNext(_ matches: @escaping (Call) -> Bool, perform action: @escaping () -> Void) {
        lock.withLock { interceptions.append(Interception(matches: matches, action: action)) }
    }

    private func intercept(_ call: Call) {
        let pending: Interception? = lock.withLock {
            guard let index = interceptions.firstIndex(where: { $0.matches(call) }) else { return nil }
            return interceptions.remove(at: index)
        }
        pending?.action()
    }

    /// Fait échouer toute opération `operation` visant le trousseau data protection
    /// (`dataProtection: true`) ou l'ancien (`false`).
    func fail(_ operation: Operation, dataProtection: Bool, with status: OSStatus) {
        lock.withLock { failures.append(Failure(operation: operation, dataProtection: dataProtection, status: status)) }
    }

    /// La prochaine écriture data protection réussit mais stocke autre chose que ce qui a été envoyé.
    func corruptNextDataProtectionWrite() { lock.withLock { corruptsNextDataProtectionWrite = true } }

    func copyData(matching query: [String: Any]) -> (status: OSStatus, data: Data?) {
        let call = Call(operation: .copy, query: query)
        intercept(call)
        return lock.withLock {
            recorded.append(call)
            if let status = failure(for: call) { return (status, nil) }
            guard let account = call.account, let data = store(for: call)[account] else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, data)
        }
    }

    func update(matching query: [String: Any], attributes: [String: Any]) -> OSStatus {
        let call = Call(operation: .update, query: query)
        intercept(call)
        return lock.withLock {
            recorded.append(call)
            if let status = failure(for: call) { return status }
            guard let account = call.account, store(for: call)[account] != nil else { return errSecItemNotFound }
            write(attributes[kSecValueData as String] as? Data, account: account, call: call)
            return errSecSuccess
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        let call = Call(operation: .add, query: attributes)
        intercept(call)
        return lock.withLock {
            recorded.append(call)
            if let status = failure(for: call) { return status }
            guard let account = call.account else { return errSecParam }
            guard store(for: call)[account] == nil else { return errSecDuplicateItem }
            write(attributes[kSecValueData as String] as? Data, account: account, call: call)
            return errSecSuccess
        }
    }

    func delete(matching query: [String: Any]) -> OSStatus {
        let call = Call(operation: .delete, query: query)
        intercept(call)
        return lock.withLock {
            recorded.append(call)
            if let status = failure(for: call) { return status }
            guard let account = call.account, store(for: call)[account] != nil else { return errSecItemNotFound }
            if call.usesDataProtection { dataProtection[account] = nil } else { legacy[account] = nil }
            return errSecSuccess
        }
    }

    private func store(for call: Call) -> [String: Data] { call.usesDataProtection ? dataProtection : legacy }

    private func failure(for call: Call) -> OSStatus? {
        failures.first { $0.operation == call.operation && $0.dataProtection == call.usesDataProtection }?.status
    }

    private func write(_ data: Data?, account: String, call: Call) {
        guard var value = data else { return }
        if call.usesDataProtection {
            if corruptsNextDataProtectionWrite {
                corruptsNextDataProtectionWrite = false
                value = Data("corrompu".utf8)
            }
            dataProtection[account] = value
        } else {
            legacy[account] = value
        }
    }
}
