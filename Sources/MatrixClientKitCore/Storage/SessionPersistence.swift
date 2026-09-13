import Foundation

/// Enregistre et relit les données de session dans un stockage sécurisé.
public actor SessionPersistence {
    public static let storageKey = "com.matrixclientkit.session"

    private let store: any SecureStore

    public init(store: any SecureStore) {
        self.store = store
    }

    public func save(_ session: MatrixSessionData) throws {
        do {
            let data = try JSONEncoder().encode(session)
            try store.set(data, forKey: Self.storageKey)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }

    public func load() throws -> MatrixSessionData? {
        let data: Data?
        do {
            data = try store.data(forKey: Self.storageKey)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.storage(.unavailable)
        }

        guard let data else { return nil }

        do {
            return try JSONDecoder().decode(MatrixSessionData.self, from: data)
        } catch {
            throw MatrixError.storage(.corrupted)
        }
    }

    public func clear() throws {
        do {
            try store.removeValue(forKey: Self.storageKey)
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }
}
