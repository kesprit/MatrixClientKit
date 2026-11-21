import Foundation
import MatrixClientKitCore
import MatrixRustSDK

/// Traduit les types du compte entre le domaine et le SDK Rust.
enum AccountMapper {
    /// L'action amont d'une page de gestion ; `nil` pour la racine (`.overview`), que le SDK
    /// désigne par l'absence d'action. Le `switch` est exhaustif : ajouter une page au domaine
    /// sans la relier à l'amont ne compile pas.
    static func upstreamAction(
        for action: MatrixClientKitCore.AccountManagementAction
    ) -> MatrixRustSDK.AccountManagementAction? {
        switch action.kind {
        case .overview: nil
        case .profile: .profile
        case .devices: .devicesList
        case let .device(id): .deviceView(deviceId: id.rawValue)
        case let .deleteDevice(id): .deviceDelete(deviceId: id.rawValue)
        case .deactivateAccount: .accountDeactivate
        }
    }

    /// L'URL de gestion rendue par l'amont ; `nil` si le serveur ne délègue pas la gestion du
    /// compte. Une chaîne qui n'est pas une URL valide est une erreur, pas un `nil` : l'appelant
    /// y verrait à tort un serveur sans page de gestion.
    static func managementURL(from string: String?) throws -> URL? {
        guard let string else { return nil }
        guard !string.isEmpty, let url = URL(string: string), url.scheme != nil else {
            throw MatrixError.unexpected(
                message: "The account management address is not a valid URL.", details: string)
        }
        return url
    }

    /// Les identifiants amont, sans ceux qui ne sont pas des user ID valides.
    static func userIDs(from identifiers: [String]) -> [UserID] {
        identifiers.compactMap { UserID(rawValue: $0) }
    }
}
