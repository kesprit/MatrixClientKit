import CryptoKit
import Foundation

/// Empreinte hexadécimale courte et stable d'une chaîne.
///
/// - Important: calculée par SHA-256, et non par `Hasher` / `hashValue`, dont la graine change à
///   chaque lancement du processus. Une empreinte instable d'un lancement à l'autre rendrait un
///   store introuvable ou changerait l'identité d'un élément de liste sans raison visible.
enum StableDigest {
    /// Empreinte de 32 caractères hexadécimaux (128 bits), sûre pour un chemin de fichier comme
    /// pour un identifiant.
    static func short(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
    }
}
