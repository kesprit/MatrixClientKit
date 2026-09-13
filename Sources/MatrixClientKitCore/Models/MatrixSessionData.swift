import Foundation

/// Données de session persistées entre deux lancements.
///
/// - Note: portée `package`. Ce type n'existait en `public` que pour être visible depuis la
///   cible Rust ; aucune API publique ne le produit ni ne le consomme, et un modèle porteur de
///   jeton n'a rien à faire dans la documentation générée.
///
/// - Warning: contient un jeton d'accès. Ce type ne doit être écrit que dans un stockage
///   sécurisé — voir ``SecureStore``.
package struct MatrixSessionData: Sendable, Hashable, Codable {
    /// Identifiant de l'utilisateur propriétaire de la session.
    package let userID: UserID
    /// Identifiant de l'appareil associé à la session.
    package let deviceID: DeviceID
    /// Adresse du homeserver auquel la session est rattachée.
    package let homeserverURL: URL
    /// Jeton d'accès utilisé pour authentifier les requêtes.
    package let accessToken: String
    /// Jeton permettant de renouveler l'accès sans nouvelle authentification, s'il existe.
    package let refreshToken: String?
    /// Données OAuth opaques à restituer au SDK amont lors de la restauration, le cas échéant.
    package let oauthData: String?
    /// Variante de sliding sync utilisée par la session : `"none"`, `"native"` ou
    /// `"discoverNative"`.
    package let slidingSyncVersion: String

    package init(
        userID: UserID,
        deviceID: DeviceID,
        homeserverURL: URL,
        accessToken: String,
        refreshToken: String?,
        oauthData: String?,
        slidingSyncVersion: String
    ) {
        self.userID = userID
        self.deviceID = deviceID
        self.homeserverURL = homeserverURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.oauthData = oauthData
        self.slidingSyncVersion = slidingSyncVersion
    }
}

extension MatrixSessionData: CustomStringConvertible, CustomDebugStringConvertible {
    /// Description expurgée : n'expose jamais le jeton d'accès ni le jeton de renouvellement.
    package var description: String {
        """
        MatrixSessionData(userID: \(userID), deviceID: \(deviceID), \
        homeserverURL: \(homeserverURL), accessToken: <redacted>, \
        refreshToken: \(refreshToken == nil ? "nil" : "<redacted>"))
        """
    }

    package var debugDescription: String { description }
}

extension UserID: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = UserID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "identifiant utilisateur invalide : \(raw)")
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension DeviceID: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = DeviceID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "identifiant d'appareil invalide : \(raw)")
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
