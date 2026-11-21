import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Traduit le profil et la présence amont vers le domaine, et inversement.
enum ProfileMapper {

    /// Un identifiant d'utilisateur amont invalide est une anomalie du serveur : `.unexpected`.
    /// Un avatar qui n'est pas une URL `mxc://` n'est pas affichable : `nil`, le reste du profil
    /// reste lisible.
    static func profile(from upstream: MatrixRustSDK.UserProfile) throws -> MatrixClientKitCore.UserProfile {
        guard let userID = UserID(rawValue: upstream.userId) else {
            throw MatrixError.unexpected(
                message: "The server returned an invalid user ID.",
                details: upstream.userId
            )
        }
        return MatrixClientKitCore.UserProfile(
            userID: userID,
            displayName: upstream.displayName,
            avatar: avatar(from: upstream.avatarUrl)
        )
    }

    /// Même règle que l'avatar de l'expéditeur dans la timeline : ``MediaSource/init(url:)``.
    private static func avatar(from url: String?) -> MatrixClientKitCore.MediaSource? {
        url.flatMap { MatrixClientKitCore.MediaSource(url: $0) }
    }

    static func upstreamPresence(from presence: Presence) -> PresenceState {
        switch presence {
        case .online: .online
        case .unavailable: .unavailable
        case .offline: .offline
        }
    }

    static func presence(from upstream: PresenceState) -> Presence {
        switch upstream {
        case .online: .online
        case .unavailable: .unavailable
        case .offline: .offline
        }
    }
}
