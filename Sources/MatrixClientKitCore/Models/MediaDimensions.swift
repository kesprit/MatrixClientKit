/// The width and height of an image or a video, in pixels.
public struct MediaDimensions: Sendable, Hashable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
