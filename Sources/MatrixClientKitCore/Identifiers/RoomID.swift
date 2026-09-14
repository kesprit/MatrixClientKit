/// A Matrix room identifier. The server part is optional: rooms in version 12 and later may
/// have none.
public struct RoomID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.hasPrefix("!"), rawValue.count > 1 else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
