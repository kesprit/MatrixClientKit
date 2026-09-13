/// Identifiant d'événement Matrix, préfixé par `$`.
public struct EventID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("$"), rawValue.count > 1 else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
