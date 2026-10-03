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

        for listed in entries {
            let name = listed.lastPathComponent
            // On ne réutilise pas l'URL listée : le système de fichiers peut la rendre sous une
            // autre forme (`/private/var`, lien symbolique) que celle dont les baux ont été pris.
            // Reconstruite depuis la même racine, elle suit le même calcul que `StoragePaths`.
            let entry = root.appendingPathComponent(name, isDirectory: true)
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory, name != kept?.directoryName, !registry.isLeased(entry), looksLikeStore(entry)
            else { continue }

            // Le nom du répertoire suffit à retrouver la clé : même mise en page pour les deux
            // segments, d'où `.session(name)` y compris pour un store legacy.
            try? LocalStore(storage: storage, segment: .session(name), secureStore: secureStore).purge()
        }
    }

    /// Un contenu étranger posé sous la racine ne doit jamais être effacé : seul un répertoire
    /// qui a la forme d'un store (`data` ou `cache`) est ramassé.
    private func looksLikeStore(_ directory: URL) -> Bool {
        ["data", "cache"].contains { name in
            var isDirectory: ObjCBool = false
            let path = directory.appendingPathComponent(name, isDirectory: true).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
