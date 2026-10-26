/// The media a received message carries.
public struct MediaAttachment: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case image, video, audio, voice, file }

    public let kind: Kind
    public let source: MediaSource
    public let filename: String
    public let caption: String?
    public let mimeType: String?
    public let size: Int?
    public let dimensions: MediaDimensions?
    public let duration: Duration?
    public let thumbnail: MediaSource?
    public let blurhash: String?

    public init(
        kind: Kind,
        source: MediaSource,
        filename: String,
        caption: String? = nil,
        mimeType: String? = nil,
        size: Int? = nil,
        dimensions: MediaDimensions? = nil,
        duration: Duration? = nil,
        thumbnail: MediaSource? = nil,
        blurhash: String? = nil
    ) {
        self.kind = kind
        self.source = source
        self.filename = filename
        self.caption = caption
        self.mimeType = mimeType
        self.size = size
        self.dimensions = dimensions
        self.duration = duration
        self.thumbnail = thumbnail
        self.blurhash = blurhash
    }
}
