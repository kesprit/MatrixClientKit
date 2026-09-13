/// Identifiant d'utilisateur Matrix, de la forme `@localpart:serveur`.
public struct UserID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("@") else { return nil }
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return nil }
        guard separator != body.startIndex else { return nil }
        guard body.index(after: separator) != body.endIndex else { return nil }
        self.rawValue = rawValue
    }

    /// Partie locale de l'identifiant, sans le `@` ni le nom de serveur.
    public var localpart: String {
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return String(body) }
        return String(body[body.startIndex..<separator])
    }

    /// Nom du serveur, port inclus s'il est présent.
    public var serverName: String {
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return "" }
        return String(body[body.index(after: separator)...])
    }

    public var description: String { rawValue }
}
