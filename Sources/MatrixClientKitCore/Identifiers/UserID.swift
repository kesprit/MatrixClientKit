/// A Matrix user identifier, of the form `@localpart:server`.
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

    /// The local part of the identifier, without the `@` or the server name.
    public var localpart: String {
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return String(body) }
        return String(body[body.startIndex..<separator])
    }

    /// The server name, including the port when one is present.
    public var serverName: String {
        let body = rawValue.dropFirst()
        guard let separator = body.firstIndex(of: ":") else { return "" }
        return String(body[body.index(after: separator)...])
    }

    public var description: String { rawValue }
}
