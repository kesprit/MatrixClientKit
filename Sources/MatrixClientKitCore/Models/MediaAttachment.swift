/// The media a received message carries.
public struct MediaAttachment: Sendable, Hashable {
    /// The kind of a received media.
    public enum Kind: Sendable, Hashable {
        /// An image.
        case image
        /// A video.
        case video
        /// An audio file that is not a voice message.
        case audio
        /// A voice message.
        case voice
        /// Any other file.
        case file
    }

    /// The kind of the media.
    public let kind: Kind
    /// Where the media lives; pass it to ``MediaService`` to read it.
    public let source: MediaSource
    /// The file name the sender gave.
    public let filename: String
    /// The caption that goes with the media, if any.
    public let caption: String?
    /// The MIME type the sender declared, if any.
    public let mimeType: String?
    /// The size in bytes the sender declared, if any.
    public let size: Int?
    /// The width and height of an image or a video, if declared.
    public let dimensions: MediaDimensions?
    /// The duration of a video, an audio file or a voice message, if declared.
    public let duration: Duration?
    /// A thumbnail the sender attached, read like any media; not the homeserver's thumbnail.
    public let thumbnail: MediaSource?
    /// A compact placeholder of an image or a video, to decode while it loads.
    public let blurhash: String?

    /// Builds a received media description, typically for a test or a preview.
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
