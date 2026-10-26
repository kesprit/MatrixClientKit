/// Where a media lives on the homeserver. Opaque: pass it back to ``MediaService``.
public struct MediaSource: Sendable, Hashable, Codable {
    /// The `mxc://` URL of the media.
    public let url: String
    /// True when the media is end-to-end encrypted; the keys travel with the source.
    public let isEncrypted: Bool
    /// Représentation amont (JSON), gardée pour reconstruire la source FFI sans perte, clés de
    /// chiffrement comprises. `nil` pour une source construite à partir d'une simple URL.
    package let upstreamJSON: String?

    /// Builds a source from an `mxc://` URL (an avatar, for instance). `nil` for any other scheme.
    public init?(url: String) {
        // Schéma insensible à la casse, avec un reste non vide après `mxc://`.
        guard url.lowercased().hasPrefix("mxc://"), url.count > "mxc://".count else { return nil }
        self.url = url
        self.isEncrypted = false
        self.upstreamJSON = nil
    }

    package init(url: String, isEncrypted: Bool, upstreamJSON: String?) {
        self.url = url
        self.isEncrypted = isEncrypted
        self.upstreamJSON = upstreamJSON
    }
}
