import Foundation
import MatrixClientKitCore

/// Supprime les stores que plus aucune session ne peut rouvrir (spec 0.4, §5.4).
///
/// Au mieux : un échec est ignoré et retenté au passage suivant, il ne fait jamais échouer une
/// connexion ni une restauration. Réservé à l'application — l'extension ne purge jamais rien
/// (spec 0.3, §7) ; c'est à l'appelant de ne pas l'invoquer avec ce rôle.
struct OrphanedStoreSweeper {
    let storage: MatrixStorage
    let secureStore: any SecureStore
    let registry: StoreRegistry

    /// - Parameter kept: le store de la session persistée, épargné même sans bail ; `nil` quand
    ///   aucune session n'est persistée.
    func sweep(keeping kept: StoreSegment?) {
        guard let root = try? StoragePaths.root(for: storage),
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else { return }

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = entry.lastPathComponent
            guard isDirectory, name != kept?.directoryName, !registry.isLeased(entry) else { continue }

            // Le nom du répertoire suffit à retrouver la clé : même mise en page pour les deux
            // segments, d'où `.session(name)` y compris pour un store legacy.
            try? LocalStore(storage: storage, segment: .session(name), secureStore: secureStore).purge()
        }
    }
}
