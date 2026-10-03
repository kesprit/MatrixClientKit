import Foundation
import MatrixRustSDK
import MatrixClientKitCore

enum LoginDetailsMapper {
    static func map(_ details: HomeserverLoginDetails, fallback: URL) -> LoginDetails {
        LoginDetails(
            homeserver: URL(string: details.url()) ?? fallback,
            supportsPassword: details.supportsPasswordLogin(),
            supportsOAuth: details.supportsOauthLogin(),
            supportsSSO: details.supportsSsoLogin(),
            oauthPrompts: Set(details.supportedOauthPrompts().compactMap(prompt))
        )
    }

    /// Un prompt inconnu n'est pas utilisable par l'application : il est ignoré (spec 0.4, §4.2).
    static func prompt(_ prompt: MatrixRustSDK.OAuthPrompt) -> MatrixClientKitCore.OAuthPrompt? {
        switch prompt {
        case .login: .login
        case .create: .create
        case .consent: .consent
        case .unknown: nil
        }
    }

    static func prompt(_ prompt: MatrixClientKitCore.OAuthPrompt) -> MatrixRustSDK.OAuthPrompt {
        switch prompt {
        case .login: .login
        case .create: .create
        case .consent: .consent
        }
    }
}
