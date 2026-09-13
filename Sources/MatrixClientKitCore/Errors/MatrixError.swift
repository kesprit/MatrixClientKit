import Foundation

/// Toutes les erreurs émises par MatrixClientKit.
///
/// - Important: les cas de premier niveau sont figés pour la durée d'une version majeure.
///   Une erreur nouvellement distinguable par le SDK sous-jacent est rapportée dans
///   ``MatrixError/unexpected(message:details:)`` jusqu'à la majeure suivante, afin qu'ajouter
///   de la précision ne casse jamais la compilation des applications.
public enum MatrixError: Error, Sendable, Hashable, LocalizedError {

    public enum Authentication: Sendable, Hashable {
        case invalidCredentials
        case unknownToken(soft: Bool)
        case userDeactivated
        case missingToken
        /// Le serveur exige la résolution d'un captcha, pas encore fournie.
        case captchaRequired
        /// Un captcha a été fourni mais refusé par le serveur.
        ///
        /// Distinct de ``captchaRequired`` : l'un demande à l'utilisateur de faire quelque chose
        /// qu'il n'a pas fait, l'autre de refaire ce qu'il a raté.
        case captchaInvalid
        case unsupportedLoginType
    }

    public enum Network: Sendable, Hashable {
        case offline
        case timeout
        case tlsFailure
    }

    public enum Permission: Sendable, Hashable {
        case forbidden
        case insufficientPowerLevel(required: Int, current: Int)
        case guestAccessForbidden
    }

    public enum Resource: Sendable, Hashable {
        case room
        case event
        case user
        case media
        /// Le serveur n'a pas précisé quelle ressource est introuvable.
        case unspecified
    }

    public enum Encryption: Sendable, Hashable {
        case unableToDecrypt(reason: String)
        case verificationRequired
        case invalidRecoveryKey
    }

    public enum Server: Sendable, Hashable {
        case resourceLimitExceeded(adminContact: String)
        case unsupportedRoomVersion
        case maintenance
        case invalidResponse
    }

    public enum Storage: Sendable, Hashable {
        case unavailable
        case corrupted
        case keychainFailure(status: Int32)
    }

    case authentication(Authentication)
    case network(Network)
    case rateLimited(retryAfter: Duration?)
    case permission(Permission)
    case notFound(Resource)
    case encryption(Encryption)
    case server(Server)
    case storage(Storage)
    case unexpected(message: String, details: String?)

    /// Indique si réessayer la même opération a une chance d'aboutir sans action de l'utilisateur.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited:
            return true
        case let .network(network):
            switch network {
            case .offline, .timeout: return true
            case .tlsFailure: return false
            }
        case let .server(server):
            switch server {
            case .maintenance, .invalidResponse: return true
            case .resourceLimitExceeded, .unsupportedRoomVersion: return false
            }
        case .authentication, .permission, .notFound, .encryption, .storage, .unexpected:
            return false
        }
    }

    /// Délai indiqué par le serveur avant un nouvel essai, le cas échéant.
    public var retryAfter: Duration? {
        guard case let .rateLimited(delay) = self else { return nil }
        return delay
    }

    /// Description **de diagnostic**, en français, destinée aux journaux et aux rapports de bug.
    ///
    /// - Important: ce n'est pas de la copy d'interface. Ces chaînes mêlent une phrase rédigée et
    ///   le nom du cas Swift imbriqué, ne sont pas localisées, et leur formulation peut changer
    ///   d'une version à l'autre sans que ce soit un changement cassant. Une application doit
    ///   faire correspondre les cas de ``MatrixError`` à ses propres textes localisés plutôt que
    ///   d'afficher cette valeur telle quelle. La localisation du package est hors périmètre v0.1.
    public var errorDescription: String? {
        switch self {
        case let .authentication(value): return "Erreur d'authentification : \(value)"
        case let .network(value): return "Erreur réseau : \(value)"
        case let .rateLimited(delay):
            guard let delay else { return "Trop de requêtes. Réessayez plus tard." }
            return "Trop de requêtes. Réessayez dans \(delay)."
        case let .permission(value): return "Permission refusée : \(value)"
        case let .notFound(resource): return "Ressource introuvable : \(resource)"
        case let .encryption(value): return "Erreur de chiffrement : \(value)"
        case let .server(value): return "Erreur du serveur : \(value)"
        case let .storage(value): return "Erreur de stockage : \(value)"
        case let .unexpected(message, details):
            // Toute erreur amont non encore distinguée atterrit ici (règle d'évolution du type),
            // y compris celles dont le SDK ne fournit aucun message. Rendre la chaîne vide
            // laisserait une interface afficher un cadre d'erreur sans une ligne de texte.
            let text = message.isEmpty ? "Erreur inattendue du SDK Matrix." : message
            guard let details, !details.isEmpty else { return text }
            return "\(text) (\(details))"
        }
    }
}
