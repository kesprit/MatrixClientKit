/// The width and height of an image or a video, in pixels.
public struct MediaDimensions: Sendable, Hashable, Codable {
    /// The width, in pixels.
    public let width: Int
    /// The height, in pixels.
    public let height: Int

    /// Builds dimensions from a width and a height, in pixels.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
