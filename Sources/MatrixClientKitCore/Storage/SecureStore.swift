import Foundation

/// Stockage de secrets. Abstrait pour que la logique de persistance reste testable
/// sans dépendre du Keychain.
///
/// - Note: portée `package`. Aucun point d'entrée public n'accepte un stockage injecté —
///   ``Matrix/client(homeserver:storage:)`` construit lui-même son magasin Keychain —, donc
///   publier ce vocabulaire reviendrait à geler une API que personne ne peut utiliser.
package protocol SecureStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

/// Implémentation en mémoire, destinée aux tests et aux mocks.
package final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    package init() {}

    package func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    package func set(_ data: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    package func removeValue(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
