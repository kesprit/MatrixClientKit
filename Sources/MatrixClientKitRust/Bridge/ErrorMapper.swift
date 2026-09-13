import Foundation
import MatrixRustSDK
import MatrixClientKitCore

/// Traduit les erreurs du SDK Rust vers ``MatrixError``.
enum ErrorMapper {

    static func map(_ error: any Error) -> MatrixError {
        switch error {
        case let error as ClientError:
            return map(error)
        case let error as MatrixError:
            return error
        default:
            return .unexpected(message: String(describing: error), details: nil)
        }
    }

    static func map(_ error: ClientError) -> MatrixError {
        switch error {
        case let .Generic(msg, details):
            return .unexpected(message: msg, details: details)
        case let .MatrixApi(kind, code, msg, details):
            return map(kind: kind, code: code, message: msg, details: details)
        case let .ContentScanner(reason, info):
            return .unexpected(message: "Content scanner: \(reason)", details: info)
        }
    }

    static func map(
        kind: ErrorKind,
        code: String,
        message: String,
        details: String?
    ) -> MatrixError {
        // Certaines conditions ne sont distinguables que par le code d'erreur Matrix.
        if code == "M_USER_DEACTIVATED" {
            return .authentication(.userDeactivated)
        }

        switch kind {
        case .forbidden:
            return .permission(.forbidden)
        case .guestAccessForbidden:
            return .permission(.guestAccessForbidden)
        case let .limitExceeded(retryAfterMs):
            return .rateLimited(retryAfter: retryAfterMs.map { .milliseconds(Int64(clamping: $0)) })
        case let .unknownToken(softLogout):
            return .authentication(.unknownToken(soft: softLogout))
        case .missingToken:
            return .authentication(.missingToken)
        case .unauthorized:
            return .authentication(.invalidCredentials)
        case .captchaNeeded:
            return .authentication(.captchaRequired)
        case .captchaInvalid:
            return .authentication(.captchaInvalid)
        case .notFound:
            return .notFound(.unspecified)
        case .connectionFailed:
            return .network(.offline)
        case .connectionTimeout:
            return .network(.timeout)
        case .serverNotTrusted:
            return .network(.tlsFailure)
        case let .resourceLimitExceeded(adminContact):
            return .server(.resourceLimitExceeded(adminContact: adminContact))
        case .unsupportedRoomVersion, .incompatibleRoomVersion:
            return .server(.unsupportedRoomVersion)
        case .notJson, .badJson:
            return .server(.invalidResponse)
        default:
            return .unexpected(message: message, details: detailsIncludingCode(code, details))
        }
    }

    /// Traduit une erreur survenue pendant une authentification — connexion ou restauration de
    /// session.
    ///
    /// - Important: le protocole Matrix répond `M_FORBIDDEN` aussi bien à « vous n'avez pas le
    ///   droit de faire cela » qu'à « ces identifiants sont refusés ». Seul le contexte de
    ///   l'appel permet de trancher. Hors authentification, ``MatrixError/permission(_:)`` est la
    ///   lecture juste ; pendant une authentification, c'est ``MatrixError/authentication(_:)``,
    ///   et la différence est tout sauf cosmétique : une application qui reçoit une erreur de
    ///   permission ne sait pas qu'elle doit redemander un mot de passe, et une session morte ne
    ///   serait jamais effacée puisque la purge ne se déclenche que sur la famille
    ///   `.authentication`.
    ///
    ///   Constaté contre un homeserver réel : un mot de passe erroné produit
    ///   `M_FORBIDDEN: Wrong username or password.`
    static func mapAuthentication(_ error: any Error) -> MatrixError {
        let mapped = map(error)
        guard case .permission(.forbidden) = mapped else { return mapped }
        return .authentication(.invalidCredentials)
    }

    private static func detailsIncludingCode(_ code: String, _ details: String?) -> String {
        guard let details, !details.isEmpty else { return code }
        return "\(code): \(details)"
    }
}
