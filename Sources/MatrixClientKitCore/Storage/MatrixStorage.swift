import Foundation

/// Emplacement et protection des données persistées par le SDK.
public struct MatrixStorage: Sendable, Hashable {

    /// Moment à partir duquel les secrets sont lisibles.
    ///
    /// - Important: une extension de notification s'exécute appareil verrouillé. Avec
    ///   ``whenUnlocked``, elle ne peut pas lire le jeton et la notification arrive vide.
    ///   ``afterFirstUnlock`` est le défaut pour cette raison.
    public enum KeychainAccessibility: Sendable, Hashable {
        case afterFirstUnlock
        case whenUnlocked
    }

    public enum Location: Sendable, Hashable {
        case appGroup(identifier: String)
        case local(directory: URL)
    }

    public let location: Location
    public let keychainAccessGroup: String?
    public let accessibility: KeychainAccessibility

    /// Stockage partagé entre l'application et ses extensions.
    public static func appGroup(
        _ identifier: String,
        keychainAccessGroup: String? = nil,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) -> MatrixStorage {
        MatrixStorage(
            location: .appGroup(identifier: identifier),
            keychainAccessGroup: keychainAccessGroup,
            accessibility: accessibility
        )
    }

    /// Stockage propre au processus courant, sans partage avec une extension.
    public static func local(
        directory: URL,
        accessibility: KeychainAccessibility = .afterFirstUnlock
    ) -> MatrixStorage {
        MatrixStorage(location: .local(directory: directory), keychainAccessGroup: nil, accessibility: accessibility)
    }
}
