import Foundation

/// Données de session persistées entre deux lancements.
///
/// - Warning: contient un jeton d'accès. Ce type ne doit être écrit que dans un stockage
///   sécurisé — voir ``SecureStore``.
public struct MatrixSessionData: Sendable, Hashable, Codable {
    /// Identifiant de l'utilisateur propriétaire de la session.
    public let userID: UserID
    /// Identifiant de l'appareil associé à la session.
    public let deviceID: DeviceID
    /// Adresse du homeserver auquel la session est rattachée.
    public let homeserverURL: URL
    /// Jeton d'accès utilisé pour authentifier les requêtes.
    public let accessToken: String
    /// Jeton permettant de renouveler l'accès sans nouvelle authentification, s'il existe.
    public let refreshToken: String?
    /// Données OAuth opaques à restituer au SDK amont lors de la restauration, le cas échéant.
    public let oauthData: String?
    /// Variante de sliding sync utilisée par la session : `"none"`, `"native"` ou
    /// `"discoverNative"`.
    public let slidingSyncVersion: String

    public init(
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
    public var description: String {
        """
        MatrixSessionData(userID: \(userID), deviceID: \(deviceID), \
        homeserverURL: \(homeserverURL), accessToken: <redacted>, \
        refreshToken: \(refreshToken == nil ? "nil" : "<redacted>"))
        """
    }

    public var debugDescription: String { description }
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
