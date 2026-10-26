import Foundation
import MatrixClientKitCore

/// A media file for tests, backed by a real file at ``url``.
public final class MockMediaFile: MediaFile, @unchecked Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Moves the file to `destination` and returns `true`.
    public func persist(to destination: URL) throws -> Bool {
        try FileManager.default.moveItem(at: url, to: destination)
        return true
    }
}
