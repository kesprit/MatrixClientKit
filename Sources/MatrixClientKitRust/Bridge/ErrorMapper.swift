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
        case .captchaNeeded, .captchaInvalid:
            return .authentication(.captchaRequired)
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

    private static func detailsIncludingCode(_ code: String, _ details: String?) -> String {
        guard let details, !details.isEmpty else { return code }
        return "\(code): \(details)"
    }
}
