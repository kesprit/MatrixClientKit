import Foundation

/// A media to send with ``Timeline/send(_:)``.
public struct Attachment: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// A local file; it must stay in place until the upload ends.
        case file(URL)
        /// Bytes in memory, with the file name shown to recipients.
        case data(Data, filename: String)
    }

    public enum Kind: Sendable, Hashable {
        case image(dimensions: MediaDimensions?, blurhash: String?)
        case video(dimensions: MediaDimensions?, duration: Duration?, blurhash: String?)
        case audio(duration: Duration?)
        /// A voice message; `waveform` holds values between 0 and 1.
        case voice(duration: Duration?, waveform: [Float])
        case file
    }

    public struct Thumbnail: Sendable, Hashable {
        public var source: Source
        public var mimeType: String
        public var dimensions: MediaDimensions?

        public init(source: Source, mimeType: String, dimensions: MediaDimensions? = nil) {
            self.source = source
            self.mimeType = mimeType
            self.dimensions = dimensions
        }
    }

    public var source: Source
    public var kind: Kind
    public var mimeType: String
    public var caption: String?
    /// Used for images, videos and files; ignored for audio and voice.
    public var thumbnail: Thumbnail?

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
