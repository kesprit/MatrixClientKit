import Foundation

/// Stockage de secrets. Abstrait pour que la logique de persistance reste testable
/// sans dépendre du Keychain.
public protocol SecureStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

/// Implémentation en mémoire, destinée aux tests et aux mocks.
public final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ data: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public func removeValue(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
