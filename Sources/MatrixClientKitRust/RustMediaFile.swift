import Foundation
import MatrixClientKitCore

/// Implémentation de ``MediaFile`` adossée au handle de fichier du SDK Rust.
///
/// Le handle amont supprime le fichier quand il est libéré : le retenir fait vivre le fichier.
final class RustMediaFile: MediaFile {
    let url: URL
    private let lifetime: ClientLifetime?
    /// Libéré par ``deinit`` à travers ``lifetime``, client encore vivant. Écrit seulement par
    /// l'initialiseur et par ``deinit``, d'où `nonisolated(unsafe)`.
    nonisolated(unsafe) private var handle: (any MediaFileHandleDriving)?

    init(handle: any MediaFileHandleDriving, lifetime: ClientLifetime?) throws {
        self.url = URL(fileURLWithPath: try handle.path())
        self.handle = handle
        self.lifetime = lifetime
    }

    deinit {
        if let lifetime {
            lifetime.release(&handle)
        } else {
            handle = nil
        }
    }

    func persist(to destination: URL) throws -> Bool {
        guard let handle else {
            // Inatteignable : `handle` n'est vidé que par `deinit`.
            preconditionFailure("RustMediaFile used after deinitialization")
        }
        do {
            return try handle.persist(path: destination.path)
        } catch {
            throw ErrorMapper.map(error)
        }
    }
}
