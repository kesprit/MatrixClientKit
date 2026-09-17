import Foundation

/// Every error MatrixClientKit throws.
///
/// - Important: the top-level cases are frozen for the lifetime of a major version. An error the
///   underlying SDK newly lets us distinguish is reported through
///   ``MatrixError/unexpected(message:details:)`` until the next major, so that adding precision
///   never breaks an application's build.
public enum MatrixError: Error, Sendable, Hashable, LocalizedError {

    public enum Authentication: Sendable, Hashable {
        case invalidCredentials
        case unknownToken(soft: Bool)
        case userDeactivated
        case missingToken
        /// The server requires a captcha that has not been solved yet.
        case captchaRequired
        /// A captcha was provided and the server rejected it.
        ///
        /// Distinct from ``captchaRequired``: one asks the user to do something they have not
        /// done, the other to redo something they got wrong.
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
        /// The server did not say which resource was missing.
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

    /// Whether retrying the same operation could succeed without the user doing anything.
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

    /// The delay the server asked for before retrying, when it gave one.
    public var retryAfter: Duration? {
        guard case let .rateLimited(delay) = self else { return nil }
        return delay
    }

    /// A **diagnostic** description, meant for logs and bug reports.
    ///
    /// - Important: this is not interface copy. These strings splice a written sentence onto the
    ///   name of the nested Swift case, are not localised, and their wording may change between
    ///   versions without that being a breaking change. An application should map ``MatrixError``
    ///   cases to its own localised copy rather than displaying this value. Localising the
    ///   package is out of scope for now.
    public var errorDescription: String? {
        switch self {
        case let .authentication(value): return "Authentication error: \(value)"
        case let .network(value): return "Network error: \(value)"
        case let .rateLimited(delay):
            guard let delay else { return "Too many requests. Try again later." }
            return "Too many requests. Try again in \(delay)."
        case let .permission(value): return "Permission denied: \(value)"
        case let .notFound(resource): return "Not found: \(resource)"
        case let .encryption(value): return "Encryption error: \(value)"
        case let .server(value): return "Server error: \(value)"
        case let .storage(value): return "Storage error: \(value)"
        case let .unexpected(message, details):
            // Toute erreur amont non encore distinguée atterrit ici (règle d'évolution du type),
            // y compris celles dont le SDK ne fournit aucun message. Rendre la chaîne vide
            // laisserait une interface afficher un cadre d'erreur sans une ligne de texte.
            let text = message.isEmpty ? "Unexpected Matrix SDK error." : message
            guard let details, !details.isEmpty else { return text }
            return "\(text) (\(details))"
        }
    }
}
