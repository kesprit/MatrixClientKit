import Foundation

/// A media to send with ``Timeline/send(_:)``.
public struct Attachment: Sendable, Hashable {
    /// Where the bytes to send come from.
    public enum Source: Sendable, Hashable {
        /// A local file; it must stay in place until the upload ends.
        case file(URL)
        /// Bytes in memory, with the file name shown to recipients.
        case data(Data, filename: String)
    }

    /// What the media is, with the details recipients use to preview it — all produced by your
    /// application.
    public enum Kind: Sendable, Hashable {
        /// An image, with its dimensions and blurhash when known.
        case image(dimensions: MediaDimensions?, blurhash: String?)
        /// A video, with its dimensions, duration and blurhash when known.
        case video(dimensions: MediaDimensions?, duration: Duration?, blurhash: String?)
        /// An audio file that is not a voice message, with its duration when known.
        case audio(duration: Duration?)
        /// A voice message; `waveform` holds values between 0 and 1.
        case voice(duration: Duration?, waveform: [Float])
        /// Any other file.
        case file
    }

    /// A thumbnail your application produced for an image or a video.
    public struct Thumbnail: Sendable, Hashable {
        /// Where the thumbnail's bytes come from.
        public var source: Source
        /// The thumbnail's MIME type, `image/jpeg` for instance.
        public var mimeType: String
        /// The thumbnail's width and height, when known.
        public var dimensions: MediaDimensions?

        /// Builds a thumbnail from its bytes, MIME type and, optionally, dimensions.
        public init(source: Source, mimeType: String, dimensions: MediaDimensions? = nil) {
            self.source = source
            self.mimeType = mimeType
            self.dimensions = dimensions
        }
    }

    /// Where the media's bytes come from.
    public var source: Source
    /// What the media is.
    public var kind: Kind
    /// The media's MIME type, `image/jpeg` for instance.
    public var mimeType: String
    /// A caption sent with the media.
    public var caption: String?
    /// Used for images and videos; ignored, without being read, for audio, voice messages and files.
    public var thumbnail: Thumbnail?

    /// Builds an attachment; only the source, the kind and the MIME type are required.
    public init(
        source: Source,
        kind: Kind,
        mimeType: String,
        caption: String? = nil,
        thumbnail: Thumbnail? = nil
    ) {
        self.source = source
        self.kind = kind
        self.mimeType = mimeType
        self.caption = caption
        self.thumbnail = thumbnail
    }
}
