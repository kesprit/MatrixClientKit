import Foundation
import Synchronization

/// Les stores ouverts dans ce processus : tentatives de connexion en cours et sessions vivantes
/// (spec 0.4, §5.4).
///
/// Le ramassage des orphelins ne peut pas se fier à la seule session persistée : l'entrée
/// Keychain est unique par service, et une seconde connexion dans le même processus l'écrase
/// pendant que la première session tourne encore. Un bail compté par répertoire répond à la seule
/// question utile — « quelqu'un, ici, utilise-t-il ce store ? ». Compté, parce qu'une reconnexion
/// tient brièvement deux baux sur le même store.
///
/// Portée `package` pour figurer dans l'initialiseur `package` de ``SessionRestorer``.
package final class StoreRegistry: Sendable {
    package static let shared = StoreRegistry()

    private let counts = Mutex<[String: Int]>([:])

    package init() {}

    func lease(_ paths: StoragePaths) -> StoreLease {
        let key = Self.key(paths.storeDirectory)
        counts.withLock { $0[key, default: 0] += 1 }
        return StoreLease(key: key, registry: self)
    }

    func isLeased(_ directory: URL) -> Bool {
        counts.withLock { ($0[Self.key(directory)] ?? 0) > 0 }
    }

    fileprivate func release(_ key: String) {
        counts.withLock { counts in
            let remaining = (counts[key] ?? 1) - 1
            counts[key] = remaining > 0 ? remaining : nil
        }
    }

    /// Clé purement lexicale : ni résolution de lien symbolique, ni `standardizedFileURL`, qui
    /// retire `/private` seulement quand le chemin existe. Un bail pris avant la création du
    /// répertoire et un test fait après n'auraient sinon pas la même clé (`/var` contre
    /// `/private/var`, racine en lien symbolique). Le ramassage reconstruit donc ses candidats
    /// depuis la même racine que le bail.
    private static func key(_ directory: URL) -> String {
        directory.path
    }
}

/// Un bail sur un store. Libéré explicitement ou à la libération de son porteur.
///
/// - Important: le porteur (la session ou la tentative de connexion) doit le stocker dans une
///   propriété. Une simple variable locale jamais relue peut voir sa durée de vie close par
///   l'optimiseur, ce qui libérerait le bail trop tôt et exposerait un store vivant au ramassage.
final class StoreLease: Sendable {
    private let key: String
    private let registry: StoreRegistry
    private let released = Mutex(false)

    fileprivate init(key: String, registry: StoreRegistry) {
        self.key = key
        self.registry = registry
    }

    func release() {
        let wasReleased = released.withLock { released in
            defer { released = true }
            return released
        }
        if !wasReleased { registry.release(key) }
    }

    deinit { release() }
}
