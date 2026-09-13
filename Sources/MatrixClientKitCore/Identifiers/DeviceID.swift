/// Identifiant d'appareil, opaque et propre au homeserver.
public struct DeviceID: Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}
