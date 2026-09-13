/// Identifiant de room Matrix. La partie serveur est optionnelle : les rooms en version 12
/// et ultérieures peuvent en être dépourvues.
public struct RoomID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("!"), rawValue.count > 1 else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
