import Foundation
import MatrixRustSDK
import MatrixClientKitCore

enum OAuthMapper {
    static func configuration(
        _ configuration: MatrixClientKitCore.OAuthConfiguration
    ) -> MatrixRustSDK.OAuthConfiguration {
        MatrixRustSDK.OAuthConfiguration(
            clientName: configuration.clientName,
            redirectUri: configuration.redirectURI.absoluteString,
            clientUri: configuration.clientURI.absoluteString,
            logoUri: configuration.logoURI?.absoluteString,
            tosUri: configuration.termsOfServiceURI?.absoluteString,
            policyUri: configuration.policyURI?.absoluteString,
            // Deux `URL` distinctes peuvent partager la même chaîne absolue (une URL relative à une
            // base, par exemple) : la clé amont étant une chaîne, une construction à clés uniques
            // ferait planter l'application sur une entrée qu'elle fournit elle-même.
            staticRegistrations: Dictionary(
                configuration.staticRegistrations.map { ($0.key.absoluteString, $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    /// Spec 0.4, §6. Rend `CancellationError` pour une annulation, `MatrixError` sinon.
    static func map(_ error: any Error) -> any Error {
        guard let error = error as? OAuthError else { return ErrorMapper.mapAuthentication(error) }
        switch error {
        case .NotSupported:
            return MatrixError.authentication(.unsupportedLoginType)
        case .MetadataInvalid:
            return MatrixError.server(.invalidResponse)
        case .Cancelled:
            return CancellationError()
        case let .CallbackUrlInvalid(message):
            return MatrixError.unexpected(
                message: "The authorization server's callback URL is not valid.", details: message)
        case let .Generic(message):
            return MatrixError.unexpected(message: "OAuth sign-in failed.", details: message)
        }
    }
}
