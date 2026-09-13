import Foundation

/// Enregistre et relit les données de session dans un stockage sécurisé.
///
/// - Note: portée `package`, comme ``SecureStore`` : aucun point d'entrée public n'expose la
///   persistance de session.
/// - Note: type synchrone et non un `actor` : ``SecureStore`` est déjà sûr en concurrence — le
///   Keychain l'est par construction, et l'implémentation en mémoire porte son verrou. Un acteur
///   n'ajouterait aucune garantie, et rendrait cette persistance inutilisable depuis le delegate
///   de session du SDK, dont les deux méthodes sont synchrones.
package struct SessionPersistence: Sendable {
    package static let storageKey = "com.matrixclientkit.session"

    private let store: any SecureStore

    package init(store: any SecureStore) {
        self.store = store
    }

    package func save(_ session: MatrixSessionData) throws {
        do {
            let data = try JSONEncoder().encode(session)
            try store.set(data, forKey: Self.storageKey)
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }

    package func load() throws -> MatrixSessionData? {
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

    package func clear() throws {
        do {
            try store.removeValue(forKey: Self.storageKey)
        } catch {
            throw MatrixError.storage(.unavailable)
        }
    }
}
