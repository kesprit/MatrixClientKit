/// Where a media lives on the homeserver. Opaque: pass it back to ``MediaService``.
///
/// - Important: the `Codable` encoding of an encrypted source contains its decryption keys. Store
///   it as sensitive data — in the Keychain or an encrypted store, not in plain user defaults or
///   logs. ``description``, ``debugDescription`` and reflection (`dump`, the debugger) show only
///   ``url`` and ``isEncrypted``.
public struct MediaSource: Sendable, Hashable, Codable {
    /// The `mxc://` URL of the media.
    public let url: String
    /// True when the media is end-to-end encrypted; the keys travel with the source.
    public let isEncrypted: Bool
    /// Représentation amont (JSON), gardée pour reconstruire la source FFI sans perte, clés de
    /// chiffrement comprises. `nil` pour une source construite à partir d'une simple URL.
    package let upstreamJSON: String?

    // Format d'encodage figé : ces noms sont lus par les caches déjà écrits par les applications.
    private enum CodingKeys: String, CodingKey {
        case url
        case isEncrypted
        case upstreamJSON
    }

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

// Les rendus textuels et le miroir taisent `upstreamJSON` : il porte la clé, l'IV et les
// empreintes d'un fichier chiffré, qui ne doivent pas finir dans un journal.
extension MediaSource: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The URL and whether the media is encrypted; never the decryption keys.
    public var description: String {
        "MediaSource(url: \(url), isEncrypted: \(isEncrypted))"
    }

    /// Same as ``description``: the decryption keys are never shown.
    public var debugDescription: String { description }

    /// Exposes ``url`` and ``isEncrypted`` only, so that `dump` and the debugger hide the keys.
    public var customMirror: Mirror {
        Mirror(self, children: ["url": url, "isEncrypted": isEncrypted], displayStyle: .struct)
    }
}
