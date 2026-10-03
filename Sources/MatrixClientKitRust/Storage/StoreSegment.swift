import Foundation
import MatrixClientKitCore

/// Désigne le store local d'une session (spec 0.4, §5.1).
///
/// - `legacy` : session ouverte par la 0.1 à la 0.3, dont le store vit sous l'empreinte du user ID.
///   Jamais migrée : elle garde ce chemin jusqu'à sa déconnexion.
/// - `session` : à partir de la 0.4, un identifiant aléatoire tiré à la connexion. Le store existe
///   donc avant que le user ID soit connu, ce qu'exige la connexion par QR, qui écrit les secrets
///   reçus pendant la connexion elle-même.
enum StoreSegment: Sendable, Hashable {
    case legacy(UserID)
    case session(String)

    static func newSession() -> StoreSegment {
        .session(UUID().uuidString.lowercased())
    }

    init(_ data: MatrixSessionData) {
        self = data.storeID.map(StoreSegment.session) ?? .legacy(data.userID)
    }

    /// Nom du répertoire du store sous `MatrixClientKit/`, et suffixe de son entrée Keychain.
    /// Un UUID (avec tirets) ne peut pas coïncider avec une empreinte hexadécimale.
    var directoryName: String {
        switch self {
        case let .legacy(userID): StoragePaths.segment(for: userID)
        case let .session(id): id
        }
    }

    /// La valeur à persister dans ``MatrixSessionData/storeID``.
    var storeID: String? {
        if case let .session(id) = self { return id }
        return nil
    }
}
