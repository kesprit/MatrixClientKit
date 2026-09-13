import Foundation

/// Données de session persistées entre deux lancements.
///
/// - Warning: contient un jeton d'accès. Ce type ne doit être écrit que dans un stockage
///   sécurisé — voir ``SecureStore``.
public struct MatrixSessionData: Sendable, Hashable, Codable {
    public let userID: UserID
    public let deviceID: DeviceID
    public let homeserverURL: URL
    public let accessToken: String
    public let refreshToken: String?
    public let oauthData: String?
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
